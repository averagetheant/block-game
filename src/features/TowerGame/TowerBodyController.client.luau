-- Builds the rounded body over every block, drives it, and squashes it.
--
-- The server ships four visible cubes per piece (see TowerService.buildPiece).
-- This client builds one CSG union over them out of its own ReplicatedStorage,
-- hides the cubes render-side, and moves the union with the piece every frame.
-- What the player sees is the union; what the game *is* remains the cubes.
--
-- Client-side because that is the only place a union renders. A server-made one
-- replicates with the right Size and the right TriangleCount and still draws as a
-- tiny cube; a client's own clone of the same asset draws correctly, which the aim
-- preview has always demonstrated. It's also cheaper: nothing extra crosses the
-- wire, and a client that can't build one is left with the visible cubes, which is
-- the game as it was before bodies existed.
--
-- Same shape as the night lights in TowerZoneController — a render trick the
-- server never hears about.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BlockBody = require(ReplicatedStorage.Features.TowerGame.BlockBody)
local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)

local TowerBodyController = {}

-- The spring. Frequency is sqrt(stiffness) rad/s and `damping` is how fast it
-- dies; around 0.3 of critical leaves two visible overshoots, which is what reads
-- as jelly rather than as the block briefly getting shorter.
local STIFFNESS = 220
local DAMPING = 9

-- Impact detection, measured off the *rendered* motion rather than
-- AssemblyLinearVelocity, so the squish lands on the frame the block visibly
-- stops — replicated velocity for a server-owned part arrives in steps and would
-- fire the wobble a moment after the eye saw the hit.
--
-- The test is what *fraction* of its speed the block lost, not how much: a
-- server-owned part's CFrame replicates at around 20Hz and is interpolated
-- between, so frame-to-frame speed is noisy in proportion to how fast the block is
-- going. A block in clean free fall jitters by 10-20 studs/s a frame while a real
-- landing loses half its speed or more in one, and an absolute threshold can't
-- separate those.
local DECEL_FRACTION = 0.5
local DECEL_FLOOR = 10
local MIN_IMPACT_SPEED = 8
local FULL_IMPACT_SPEED = 90
local MIN_STRENGTH = 0.3
local COOLDOWN = 0.12

local KICK = 5.5
-- Hard clamp on the elongation. The body is exactly the size of the cubes it
-- covers, so this is also how far it may visibly overhang them.
local MAX_ELONGATION = 0.3
-- How much the other two axes bulge to make up for the squashed one. Not true
-- volume preservation — that looks like a balloon; this is the animator's version.
local SIDE_GAIN = 0.55
-- Elongation along the fall while it's still in the air. Classic squash and
-- stretch: the stretch on the way down is most of what sells the squash at the
-- bottom of it.
local FALL_STRETCH = 0.16
local FALL_FULL_SPEED = 100

type Tracked = {
	model: Model,
	root: BasePart,
	body: BasePart,
	-- Rest offset from the root cell to the body, in the root's own frame, so it
	-- survives every quarter turn.
	offset: CFrame,
	baseSize: Vector3,
	cells: { BasePart },
	e: number,
	ev: number,
	axis: number,
	lastPos: Vector3,
	lastSpeed: number,
	lastVelocity: Vector3,
	lastKickAt: number,
	pendingSpeed: number?,
	pendingDirection: Vector3,
}

local tracked: { [Model]: Tracked } = {}

-- A Noob rig wears no body, and neither does anything without the shape attribute.
local function cellsOf(model: Model): { BasePart }
	local cells = {}
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and not child:GetAttribute(Constants.BODY_ATTRIBUTE) then
			table.insert(cells, child)
		end
	end
	return cells
end

local function attach(model: Model)
	if tracked[model] or not model:IsA("Model") then
		return
	end
	if BlockBody.shapeOf(model) == nil then
		return
	end
	local cells = cellsOf(model)
	if #cells == 0 then
		return
	end
	-- Cell1 is the piece's root, the part every other cell is welded to.
	local root = model:FindFirstChild("Cell1")
	if root == nil or not root:IsA("BasePart") then
		return
	end

	-- Parented to the model so the body dies with the block — a bomb, a burn or the
	-- storm destroys the piece and takes its coat with it, no bookkeeping needed.
	local body, offset = BlockBody.build(model, root, model)
	if body == nil or offset == nil then
		return
	end

	tracked[model] = {
		model = model,
		root = root,
		body = body,
		offset = offset,
		baseSize = BlockBody.baseSizeOf(body),
		cells = cells,
		e = 0,
		ev = 0,
		axis = 2,
		lastPos = root.Position,
		lastSpeed = 0,
		lastVelocity = Vector3.zero,
		lastKickAt = 0,
		pendingSpeed = nil,
		pendingDirection = Vector3.new(0, -1, 0),
	}
end

-- Which of the body's own axes the hit came down. Size is axis-aligned in part
-- space, so an off-angle landing squashes along the nearest axis instead of the
-- true contact normal — invisible at a third of a second.
local function axisFor(entry: Tracked, direction: Vector3): number
	local localDir = entry.root.CFrame:VectorToObjectSpace(direction)
	local x, y, z = math.abs(localDir.X), math.abs(localDir.Y), math.abs(localDir.Z)
	if y >= x and y >= z then
		return 2
	end
	return if x >= z then 1 else 3
end

local function scaleFor(axis: number, e: number): Vector3
	local along = 1 + e
	local across = 1 - e * SIDE_GAIN
	if axis == 1 then
		return Vector3.new(along, across, across)
	elseif axis == 2 then
		return Vector3.new(across, along, across)
	end
	return Vector3.new(across, across, along)
end

-- Retro studs the blocks, and studs render as nothing on a rounded face — so in
-- that zone the body steps aside and the square cells are the block, which is
-- what a 1962 brick should look like anyway. Read off the cells rather than off
-- the zone, so this needs no packet and no state of its own.
local function isStudded(root: BasePart): boolean
	return root.TopSurface == Enum.SurfaceType.Studs
end

local function step(entry: Tracked, delta: number, now: number)
	local root = entry.root
	local body = entry.body

	-- The body mirrors the cells, which is how every server-side effect reaches the
	-- screen without knowing bodies exist: a bomb's red flash, a burning block
	-- charring and fading, a ghost going see-through, a zone re-dressing the tower.
	local studded = isStudded(root)
	local hidden = if studded then 1 else root.Transparency
	if body.Transparency ~= hidden then
		body.Transparency = hidden
	end
	if body.Color ~= root.Color then
		body.Color = root.Color
	end
	if body.Material ~= root.Material then
		body.Material = root.Material
	end
	-- LocalTransparencyModifier, not Transparency: it's render-side, so the server
	-- never sees it and the cell's own Transparency stays readable above as the
	-- value the body should be wearing. It doesn't stick either, which is why it's
	-- re-applied from the render loop rather than set once — the aim controller
	-- learned the same thing about the held piece.
	local hideCells = if studded then 0 else 1
	for _, cell in entry.cells do
		if cell.Parent ~= nil then
			cell.LocalTransparencyModifier = hideCells
		end
	end

	-- Rendered velocity, not the replicated one. Anchored pieces are skipped: a
	-- held piece is anchored and steered by the server, and letting go of the steer
	-- stick is a hard stop that would otherwise read as a landing.
	local position = root.Position
	local velocity = (position - entry.lastPos) / delta
	local speed = if root.Anchored then 0 else velocity.Magnitude
	entry.lastPos = position

	-- Confirm or discard last frame's candidate before looking for a new one. A
	-- block that really landed is still slow a frame later; an interpolation
	-- artifact is back up to speed.
	local hit = false
	local pending = entry.pendingSpeed
	if pending then
		entry.pendingSpeed = nil
		if speed <= pending * (1 - DECEL_FRACTION) then
			local strength = math.clamp(
				(pending - MIN_IMPACT_SPEED) / (FULL_IMPACT_SPEED - MIN_IMPACT_SPEED),
				MIN_STRENGTH,
				1
			)
			entry.axis = axisFor(entry, entry.pendingDirection)
			-- Negative: the first thing a landing does is compress.
			entry.ev -= KICK * strength
			entry.lastKickAt = now
			hit = true
		end
	end

	local lost = entry.lastSpeed - speed
	if
		not hit
		and lost >= DECEL_FLOOR
		and lost >= entry.lastSpeed * DECEL_FRACTION
		and entry.lastSpeed >= MIN_IMPACT_SPEED
		and now - entry.lastKickAt >= COOLDOWN
	then
		entry.pendingSpeed = entry.lastSpeed
		-- The direction it was travelling while it still had speed — by now it has
		-- already stopped, so this frame's velocity says nothing about the hit.
		entry.pendingDirection = if entry.lastVelocity.Magnitude > 1e-3
			then entry.lastVelocity.Unit
			else Vector3.new(0, -1, 0)
	end

	if speed > 0 then
		entry.lastVelocity = velocity
	end
	entry.lastSpeed = speed

	-- Damped spring, semi-implicit Euler. delta is clamped by the caller, or a frame
	-- hitch integrates the spring straight past its own limits.
	local accel = -STIFFNESS * entry.e - DAMPING * entry.ev
	entry.ev += accel * delta
	entry.e = math.clamp(entry.e + entry.ev * delta, -MAX_ELONGATION, MAX_ELONGATION)

	local stretch = 0
	if speed > MIN_IMPACT_SPEED and not hit then
		stretch = math.clamp(speed / FALL_FULL_SPEED, 0, 1) * FALL_STRETCH
		entry.axis = axisFor(entry, velocity.Unit)
	end

	local total = math.clamp(entry.e + stretch, -MAX_ELONGATION, MAX_ELONGATION)
	local scale = scaleFor(entry.axis, total)
	local size = entry.baseSize * scale
	if body.Size ~= size then
		body.Size = size
	end

	-- Scaling a part grows it about its own centre, which would lift a landing
	-- block off the surface it just hit by half of whatever it squashed. The
	-- compression has to happen *onto* the contact, so the body is shifted by
	-- exactly what the scale took off the axis, in the direction the hit came from.
	local lostSize = entry.baseSize * (Vector3.one - scale)
	local shift = Vector3.zero
	if entry.axis == 1 then
		shift = Vector3.new(lostSize.X * 0.5 * (if entry.pendingDirection.X > 0 then -1 else 1), 0, 0)
	elseif entry.axis == 2 then
		shift = Vector3.new(0, -lostSize.Y * 0.5, 0)
	else
		shift = Vector3.new(0, 0, lostSize.Z * 0.5 * (if entry.pendingDirection.Z > 0 then -1 else 1))
	end

	body.CFrame = root.CFrame * entry.offset * CFrame.new(shift)
end

function TowerBodyController.Start()
	-- Every block the player can see lives in one of these: the arena holds the
	-- real pieces, and the aim controller's local preview is a clone of the held
	-- piece that needs dressing exactly like the original — it carries the same
	-- shape attribute, so it gets a body by the same route with nothing special
	-- written for it.
	local function watch(container: Instance)
		for _, child in container:GetChildren() do
			if child:IsA("Model") then
				task.defer(attach, child)
			end
		end
		container.ChildAdded:Connect(function(child)
			if child:IsA("Model") then
				-- One frame of grace: a model is parented before its cells are.
				task.defer(attach, child)
			end
		end)
	end

	task.spawn(function()
		watch(workspace:WaitForChild(Constants.ARENA_NAME))
	end)
	-- The preview and the landing ghost are parented straight into workspace by the
	-- aim controller, so the same watcher covers them.
	watch(workspace)

	RunService.RenderStepped:Connect(function(delta)
		-- Clamped so a hitch (or the first frame after a checkpoint demolition)
		-- can't hand the spring a delta it explodes on.
		local stepDelta = math.min(delta, 1 / 30)
		local now = os.clock()

		for model, entry in tracked do
			-- Destroyed by the storm, a checkpoint blast, a bomb, or a burn.
			if model.Parent == nil or entry.root.Parent == nil or entry.body.Parent == nil then
				tracked[model] = nil
				continue
			end
			step(entry, stepDelta, now)
		end
	end)
end

return TowerBodyController
