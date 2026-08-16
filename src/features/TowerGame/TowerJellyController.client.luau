-- TEMP DEV MODE — jelly blocks. Delete this one file and it's gone; nothing else
-- in the game knows it exists.
--
-- Every block in the arena gets a SpecialMesh, and the mesh is squashed and
-- stretched by a damped spring driven off impacts. Purely a render trick, and
-- deliberately so: the mesh's Scale and Offset are invisible to the physics
-- engine and to every measurement TowerService makes. Resizing the *parts*
-- instead would change their mass (breaking the Anvil / Feather densities),
-- change their collision, and corrupt `partTopY` -> `restingTopY` ->
-- SPAWN_CLEARANCE, which is how a piece ends up spawning inside the tower.
--
-- Entirely client-side: the meshes are created here, so the server never sees
-- them and no other player is affected. Same shape as the night lights in
-- TowerZoneController.
--
-- Dev handles:
--   * press J in game to toggle it on and off (an A/B against the plain look)
--   * every tunable below is mirrored onto attributes of a `JellyTuning` folder
--     in Workspace during play. Select it and edit them in the Properties panel
--     and the change takes effect on the next frame — no restart, no rebuild.
--     (`_G.TowerJelly` is the same table, but Studio plugins and the MCP run in
--     their own Lua VM with their own `_G`, so it's not reachable from there.
--     The attributes are, from anywhere.)
--
-- Known rough edge while this is on: a meshed part doesn't render Glass
-- refraction or stud surfaces, so the Needoh skin and the Retro zone look
-- flatter than they do normally. Fine for feeling out the wobble; it's the
-- reason this is a toggle rather than a default.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local BlockSkins = require(ReplicatedStorage.Features.TowerGame.BlockSkins)
local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)

local TowerJellyController = {}

local MESH_NAME = "JellyMesh"

local TUNING = {
	enabled = true,
	toggleKey = Enum.KeyCode.J,

	-- The spring. Frequency is sqrt(stiffness) rad/s and `damping` is how fast it
	-- dies; around 0.3 of critical leaves two visible overshoots, which is what
	-- reads as jelly rather than as the block briefly getting shorter.
	stiffness = 220,
	damping = 9,

	-- Impact detection. Measured off the *rendered* motion rather than
	-- AssemblyLinearVelocity, so the squish lands on the frame the block visibly
	-- stops — replicated velocity for a server-owned part arrives in steps and
	-- would fire the wobble a moment after the eye saw the hit.
	--
	-- The test is what *fraction* of its speed the block lost, not how much. A
	-- server-owned part's CFrame replicates at around 20Hz and is interpolated
	-- between, so frame-to-frame speed on the client is noisy in proportion to
	-- how fast the block is going: measured live, a block in clean free fall at
	-- 100 studs/s jitters by 10-20 studs/s a frame, while a real landing loses
	-- half its speed or more in one. An absolute threshold can't separate those
	-- two — it fired ~8 times a second all the way down, and the spring never got
	-- to compress and rebound once.
	decelFraction = 0.5, -- share of its speed lost in one frame to count as a hit
	decelFloor = 10, -- ...and at least this much of it, in studs/s
	minImpactSpeed = 8, -- below this the block was drifting, not landing
	fullImpactSpeed = 90, -- and at this it's a full-strength hit
	minStrength = 0.3, -- floor, so a gentle landing still wobbles
	cooldown = 0.12, -- one kick per block per this long, like IMPACT_COOLDOWN

	kick = 5.5, -- spring velocity injected at full strength
	maxElongation = 0.45, -- hard clamp, or a hard landing turns the block inside out

	-- Master gain over every skin's own `squish`, for auditioning the whole set at
	-- once without editing six numbers in BlockSkins. 1 = ship values.
	squishScale = 1,

	sideGain = 0.55, -- how much the other two axes bulge to compensate
	fallStretch = 0.16, -- elongation along the fall while it's still in the air
	-- Measured: a piece dropped from SPAWN_CLEARANCE is doing 60-116 studs/s by
	-- the time it lands, so a lower number here saturates the stretch for most of
	-- the fall and the run-up reads as one flat pose.
	fallFullSpeed = 100,
}

-- Exposed for live tuning from the client command bar.
_G.TowerJelly = TUNING

type Cell = {
	part: BasePart,
	mesh: SpecialMesh,
	-- Cell centre relative to the piece centre, in the part's own frame. Constant
	-- while the piece is one welded body, so it's cached and only recomputed when
	-- a hit lands (a Crate shatters mid-run and its cells stop sharing a centre).
	offset: Vector3,
}

type Jelly = {
	model: Model,
	root: BasePart,
	cells: { Cell },
	-- Spring state: `e` is signed elongation along `axis` (negative = squashed).
	e: number,
	ev: number,
	axis: number,
	lastPos: Vector3,
	lastSpeed: number,
	lastVelocity: Vector3,
	lastKickAt: number,
	-- A candidate hit waiting on next frame to confirm it. Interpolation noise
	-- recovers immediately; a block that actually landed is still slow.
	pendingSpeed: number?,
	pendingDirection: Vector3,
	-- Whether the mesh is currently displaced. A settled tower writes nothing.
	dirty: boolean,
	-- The rolled skin's `squish`, scaling everything this block does. Read once
	-- at attach: a block never changes skin after it's built.
	squish: number,
}

local tracked: { [Model]: Jelly } = {}

-- ------------------------------------------------------------------ attach --

-- Blocks only. A Noob rig is a jointed model whose limbs don't share a centre,
-- and squashing it about one would tear it apart on screen.
local function isBlock(model: Model): boolean
	if model:FindFirstChildWhichIsA("Humanoid") then
		return false
	end
	return model:FindFirstChildWhichIsA("BasePart") ~= nil
end

local function attach(model: Model)
	if tracked[model] or not model:IsA("Model") or not isBlock(model) then
		return
	end

	local cells: { Cell } = {}
	local root: BasePart? = nil
	-- Children, not descendants: a piece is flat (cells are direct children), and
	-- anything hanging deeper is a sound or a label, not geometry.
	for _, part in model:GetChildren() do
		if not part:IsA("BasePart") then
			continue
		end
		local mesh = part:FindFirstChild(MESH_NAME) :: SpecialMesh?
		if mesh == nil then
			mesh = Instance.new("SpecialMesh")
			mesh.Name = MESH_NAME
			mesh.MeshType = Enum.MeshType.Brick
			mesh.Parent = part
		end
		table.insert(cells, { part = part, mesh = mesh :: SpecialMesh, offset = Vector3.zero })
		root = root or part
	end

	if root == nil then
		return
	end

	-- How soft this block's material is meant to look. A block with no skin
	-- stamped on it is something this file didn't expect to be tracking, so it
	-- gets the plain full-strength wobble rather than being silently skipped.
	local skinId = model:GetAttribute(Constants.SKIN_ATTRIBUTE)
	local skin = if typeof(skinId) == "number" then BlockSkins.get(skinId) else nil

	tracked[model] = {
		model = model,
		root = root,
		cells = cells,
		e = 0,
		ev = 0,
		axis = 2,
		lastPos = root.Position,
		lastSpeed = 0,
		lastVelocity = Vector3.zero,
		lastKickAt = 0,
		pendingSpeed = nil,
		pendingDirection = Vector3.yAxis,
		dirty = false,
		squish = if skin then skin.squish else 1,
	}
end

local function detach(jelly: Jelly)
	for _, cell in jelly.cells do
		cell.mesh:Destroy()
	end
	tracked[jelly.model] = nil
end

local function detachAll()
	for _, jelly in tracked do
		detach(jelly)
	end
end

local function attachAll()
	local arena = workspace:FindFirstChild(Constants.ARENA_NAME)
	if arena == nil then
		return
	end
	for _, child in arena:GetChildren() do
		if child:IsA("Model") then
			attach(child)
		end
	end
end

-- -------------------------------------------------------------- the squish --

-- Where each cell sits relative to the piece as a whole. Without this every cell
-- would squash about its own centre and an L-piece would come apart at the seams
-- as it wobbled; with it the piece deforms as one body.
--
-- The centre is the mean of the cell positions rather than the model's bounding
-- box, because the box is world-axis-aligned and a tipped piece would read a
-- centre that isn't its own.
local function refreshOffsets(jelly: Jelly)
	local centre = Vector3.zero
	for _, cell in jelly.cells do
		centre += cell.part.Position
	end
	centre /= #jelly.cells

	for _, cell in jelly.cells do
		cell.offset = cell.part.CFrame:VectorToObjectSpace(cell.part.Position - centre)
	end
end

-- Which of the part's own axes the hit came down. SpecialMesh.Scale is
-- axis-aligned in part space, so an off-angle landing squashes along the nearest
-- axis instead of the true contact normal — invisible at a third of a second.
local function axisFor(jelly: Jelly, direction: Vector3): number
	local localDir = jelly.root.CFrame:VectorToObjectSpace(direction)
	local x, y, z = math.abs(localDir.X), math.abs(localDir.Y), math.abs(localDir.Z)
	if y >= x and y >= z then
		return 2
	end
	return if x >= z then 1 else 3
end

local function scaleFor(axis: number, e: number): Vector3
	local along = 1 + e
	local across = 1 - e * TUNING.sideGain
	if axis == 1 then
		return Vector3.new(along, across, across)
	elseif axis == 2 then
		return Vector3.new(across, along, across)
	end
	return Vector3.new(across, across, along)
end

local function write(jelly: Jelly, e: number)
	local scale = scaleFor(jelly.axis, e)
	local shift = scale - Vector3.one
	for _, cell in jelly.cells do
		cell.mesh.Scale = scale
		-- Scaling a cell moves its centre toward the piece's, so the mesh is
		-- offset by exactly what the scale took off the distance between them.
		cell.mesh.Offset = shift * cell.offset
	end
end

local function step(jelly: Jelly, delta: number, now: number)
	local root = jelly.root

	-- Rendered velocity, not the replicated one. Anchored assemblies are skipped
	-- outright: the held piece is anchored and steered by the server, and letting
	-- go of the steer stick is a hard stop that would otherwise read as a landing.
	local position = root.Position
	local velocity = (position - jelly.lastPos) / delta
	local speed = if root.Anchored then 0 else velocity.Magnitude
	jelly.lastPos = position

	-- Confirm or discard last frame's candidate before looking for a new one. A
	-- block that really landed is still slow a frame later; an interpolation
	-- artifact is back up to speed.
	local hit = false
	local pending = jelly.pendingSpeed
	if pending then
		jelly.pendingSpeed = nil
		if speed <= pending * (1 - TUNING.decelFraction) then
			local strength = math.clamp(
				(pending - TUNING.minImpactSpeed) / (TUNING.fullImpactSpeed - TUNING.minImpactSpeed),
				TUNING.minStrength,
				1
			)
			refreshOffsets(jelly)
			jelly.axis = axisFor(jelly, jelly.pendingDirection)
			-- Negative: the first thing a landing does is compress.
			jelly.ev -= TUNING.kick * strength
			jelly.lastKickAt = now
			hit = true
		end
	end

	local lost = jelly.lastSpeed - speed
	if
		not hit
		and lost >= TUNING.decelFloor
		and lost >= jelly.lastSpeed * TUNING.decelFraction
		and jelly.lastSpeed >= TUNING.minImpactSpeed
		and now - jelly.lastKickAt >= TUNING.cooldown
	then
		jelly.pendingSpeed = jelly.lastSpeed
		-- The direction it was travelling while it still had speed — by now it has
		-- already stopped, so this frame's velocity says nothing about the hit.
		jelly.pendingDirection = if jelly.lastVelocity.Magnitude > 1e-3
			then jelly.lastVelocity.Unit
			else Vector3.yAxis
	end

	if speed > 0 then
		jelly.lastVelocity = velocity
	end
	jelly.lastSpeed = speed

	-- Damped spring, semi-implicit Euler. delta is clamped by the caller, or a
	-- frame hitch integrates the spring straight past its own limits.
	local accel = -TUNING.stiffness * jelly.e - TUNING.damping * jelly.ev
	jelly.ev += accel * delta
	jelly.e = math.clamp(jelly.e + jelly.ev * delta, -TUNING.maxElongation, TUNING.maxElongation)

	-- Stretch along the fall while it's still travelling. Classic squash and
	-- stretch: the elongation on the way down is most of what sells the squash at
	-- the bottom of it.
	local stretch = 0
	if speed > TUNING.minImpactSpeed and not hit then
		stretch = math.clamp(speed / TUNING.fallFullSpeed, 0, 1) * TUNING.fallStretch
		jelly.axis = axisFor(jelly, velocity.Unit)
	end

	-- Everything the spring produced, graded down by how soft this block's skin is
	-- meant to look. Applied here at the end rather than to the kick, so it scales
	-- the fall stretch and the landing wobble by the same amount and a rigid skin
	-- can't elongate on the way down and then refuse to squash at the bottom.
	local total = (jelly.e + stretch) * jelly.squish * TUNING.squishScale
	-- A settled tower is dozens of blocks sitting at rest; writing identity scales
	-- to all of them every frame is the one way this gets expensive.
	if math.abs(total) < 0.001 then
		if jelly.dirty then
			write(jelly, 0)
			jelly.dirty = false
		end
		return
	end

	write(jelly, total)
	jelly.dirty = true
end

-- ------------------------------------------------------------- dev tuning --

-- Mirror the tuning table onto a Workspace folder so it can be dialled in from
-- the Properties panel while the game is running. Client-created, so it costs
-- the server and every other player nothing — same as the meshes.
local function buildTuningPanel()
	local folder = Instance.new("Folder")
	folder.Name = "JellyTuning"

	for key, value in TUNING do
		-- toggleKey is an EnumItem, which isn't a legal attribute type.
		if typeof(value) == "number" or typeof(value) == "boolean" then
			folder:SetAttribute(key, value)
		end
	end

	folder.AttributeChanged:Connect(function(key)
		local value = folder:GetAttribute(key)
		local current = TUNING[key]
		-- Ignore anything that changed type under us; a nil'd attribute would
		-- otherwise poison the spring with arithmetic on nil.
		if current == nil or typeof(value) ~= typeof(current) then
			return
		end
		TUNING[key] = value

		if key == "enabled" then
			if value then
				attachAll()
			else
				detachAll()
			end
			print(`[jelly] {if value then "on" else "off"}`)
		end
	end)

	folder.Parent = workspace
	return folder
end

-- ------------------------------------------------------------------- start --

function TowerJellyController.Start()
	local panel = buildTuningPanel()

	task.spawn(function()
		local arena = workspace:WaitForChild(Constants.ARENA_NAME)

		attachAll()
		arena.ChildAdded:Connect(function(child)
			if child:IsA("Model") and TUNING.enabled then
				-- One frame of grace: the server parents the model before it has
				-- finished parenting the cells into it.
				task.defer(attach, child)
			end
		end)
	end)

	RunService.RenderStepped:Connect(function(delta)
		if not TUNING.enabled then
			return
		end

		-- Clamped so a hitch (or the first frame after a checkpoint demolition)
		-- can't hand the spring a delta it explodes on.
		local stepDelta = math.min(delta, 1 / 30)
		local now = os.clock()

		for model, jelly in tracked do
			-- Destroyed by the storm, a checkpoint blast, a bomb, or a burn.
			if model.Parent == nil or jelly.root.Parent == nil then
				tracked[model] = nil
				continue
			end
			step(jelly, stepDelta, now)
		end
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or input.KeyCode ~= TUNING.toggleKey then
			return
		end
		-- Routed through the attribute rather than the table, so the key and the
		-- Properties panel are one path: the change handler does the work and the
		-- panel never shows a stale value.
		panel:SetAttribute("enabled", not TUNING.enabled)
	end)
end

return TowerJellyController
