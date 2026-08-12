-- Authoritative core for TowerGame.
--
-- Owns: the arena, the turn queue, the held piece, the dropped blocks, the
-- tower's height, and the storm stage. Clients send *intent* (steer / spin /
-- release) and this file decides whether it happens — the held piece is a
-- server-owned Model, so its movement replicates for free and every player
-- watches the same aim.
--
-- Steering is continuous: a client sends the direction it's *holding* and this
-- file integrates the position each frame. That keeps the wire cost at two
-- packets per swipe no matter how far the piece travels, and it keeps the
-- server the only thing that ever decides where a piece is.
--
-- The whole game runs on one Z slice (Constants.PLANE_Z). Roblox has no 2D
-- physics mode, so `clampToPlane` zeroes out-of-plane velocity every frame and
-- nudges back any block that still drifts. Pieces then tip and topple in-plane
-- like Tricky Towers instead of scattering into a 3D pile.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)
local Packets = require(ReplicatedStorage.Features.TowerGame.Packets)
local Shapes = require(ReplicatedStorage.Features.TowerGame.Shapes)

-- Server-realm sibling (ServerScriptService.Features.TowerGame.TowerStatsService).
local TowerStatsService = require(script.Parent.TowerStatsService)

type Block = {
	model: Model,
	root: BasePart,
	-- Only settled blocks count toward the height, so a piece still falling
	-- through the air can't spike the readout.
	settled: boolean,
}

type Held = {
	model: Model,
	root: BasePart,
	shape: Shapes.Shape,
	pivot: CFrame,
	player: Player,
}

local TowerService = {}

-- Gameplay band: after PlayerData (1) / Notes (5), before leaf services.
TowerService.Priority = 20

local PHASE = Constants.PHASE

local arena: Folder
local base: BasePart
local baseTopY = 0

local queue: { Player } = {}
local blocks: { Block } = {}
local held: Held? = nil
-- The direction the holder is currently holding: -1, 0, or 1.
local steerDir = 0
local nextShape: Shapes.Shape = Shapes.random()
local lastBroadcast = 0

-- Mirrors the State packet exactly; `broadcast` ships it as-is.
local state = {
	phase = PHASE.IDLE,
	holderUserId = 0,
	turnEndsAt = 0,
	height = 0,
	maxHeight = 0,
	blockCount = 0,
	shapeId = 0,
	nextShapeId = nextShape.id,
	order = {},
	targetHeight = Constants.STORM_FIRST_TARGET,
	stormEndsAt = 0,
	checkpoints = 0,
}

-- Turn order for the HUD: whoever holds the piece first, then the queue in the
-- order they'll play. `queue` already rotates the holder to the back on their
-- turn, so the tail of this list is the player who went immediately before.
local function buildOrder(): { number }
	local order = {}
	if state.holderUserId ~= 0 then
		table.insert(order, state.holderUserId)
	end
	for _, player in queue do
		if player.UserId ~= state.holderUserId then
			table.insert(order, player.UserId)
		end
	end
	return order
end

local function broadcast()
	state.blockCount = #blocks
	state.order = buildOrder()
	lastBroadcast = os.clock()
	Packets.State.sendToAll(state)
end

-- ---------------------------------------------------------------- the arena --

-- A Studio-authored platform wins if one is tagged; otherwise we generate the
-- prototype slab so the game is playable in an empty place.
local function findOrBuildBase(): BasePart
	for _, tagged in CollectionService:GetTagged(Constants.BASE_TAG) do
		if tagged:IsA("BasePart") then
			return tagged
		end
	end

	local part = Instance.new("Part")
	part.Name = "Base"
	part.Anchored = true
	part.Size = Constants.PLATFORM_SIZE
	part.Position = Constants.BASE_POSITION
	part.Color = Constants.BASE_COLOR
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CustomPhysicalProperties = Constants.BLOCK_PHYSICS
	part.Parent = arena
	CollectionService:AddTag(part, Constants.BASE_TAG)
	return part
end

local function buildArena()
	arena = workspace:FindFirstChild(Constants.ARENA_NAME) :: Folder
	if not arena then
		arena = Instance.new("Folder")
		arena.Name = Constants.ARENA_NAME
		arena.Parent = workspace
	end

	base = findOrBuildBase()
	baseTopY = base.Position.Y + base.Size.Y / 2
	-- Published for the client camera; see Constants.BASE_TOP_ATTRIBUTE.
	arena:SetAttribute(Constants.BASE_TOP_ATTRIBUTE, baseTopY)
end

-- --------------------------------------------------------------- the pieces --

local function buildPiece(shape: Shapes.Shape): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = `Piece_{shape.name}`

	local root: BasePart? = nil
	for index, cell in shape.cells do
		local part = Instance.new("Part")
		part.Name = `Cell{index}`
		part.Size = Vector3.new(Constants.BLOCK_SIZE, Constants.BLOCK_SIZE, Constants.BLOCK_DEPTH)
		part.Color = shape.color
		part.Material = Enum.Material.SmoothPlastic
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.CustomPhysicalProperties = Constants.BLOCK_PHYSICS
		part.Anchored = true
		part.CFrame = CFrame.new(cell.X * Constants.BLOCK_SIZE, cell.Y * Constants.BLOCK_SIZE, Constants.PLANE_Z)
		part.Parent = model
		if root == nil then
			root = part
		end
	end

	local rootPart = root :: BasePart
	-- Weld the cells into one rigid body up front. Welds are inert while the
	-- parts are anchored, so the piece becomes a single assembly the instant
	-- `release` unanchors it.
	for _, part in model:GetChildren() do
		if part == rootPart or not part:IsA("BasePart") then
			continue
		end
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = rootPart
		weld.Part1 = part
		weld.Parent = rootPart
	end

	-- Pivot at the bounding-box center so a quarter turn spins in place instead
	-- of swinging the piece around its first cell. Deliberately NO PrimaryPart:
	-- when one is set, `GetPivot`/`PivotTo` use that part's CFrame and ignore
	-- WorldPivot, which would put the rotation axis through the first cell.
	model.WorldPivot = model:GetBoundingBox()
	return model, rootPart
end

-- Where a fresh piece appears: clear of whatever has been built so far.
local function spawnPivot(): CFrame
	return CFrame.new(0, baseTopY + math.max(state.height, 0) + Constants.SPAWN_CLEARANCE, Constants.PLANE_Z)
end

-- ------------------------------------------------------------- the intents --
--
-- Every presentation (HUD buttons, keyboard, gamepad) funnels into these three.
-- They are the only writers of `held`.

-- Set the direction the holder is holding. The move itself happens in
-- `stepHeld`, so this is just a validated write of a sign.
function TowerService.setSteer(player: Player, dir: number)
	local piece = held
	if piece == nil or piece.player ~= player or state.phase ~= PHASE.AIMING then
		return
	end
	-- Direction is a sign, not a distance — a client can't ask for a 50-stud step
	-- or a 10x speed multiplier.
	steerDir = if dir > 0 then 1 elseif dir < 0 then -1 else 0
end

-- Continuous horizontal motion, integrated per frame.
local function stepHeld(deltaTime: number)
	local piece = held
	if piece == nil or steerDir == 0 or state.phase ~= PHASE.AIMING then
		return
	end

	local position = piece.pivot.Position
	local targetX = math.clamp(
		position.X + steerDir * Constants.STEER_SPEED * deltaTime,
		-Constants.STEER_LIMIT_X,
		Constants.STEER_LIMIT_X
	)
	if targetX == position.X then
		return
	end

	piece.pivot = CFrame.new(targetX, position.Y, Constants.PLANE_Z) * piece.pivot.Rotation
	piece.model:PivotTo(piece.pivot)
end

-- Absolute placement (PC mouse aiming): put the piece where the player is
-- pointing. Same authority as steering — the client proposes an X, the server
-- clamps it to the legal range.
function TowerService.aim(player: Player, x: number)
	local piece = held
	if piece == nil or piece.player ~= player or state.phase ~= PHASE.AIMING then
		return
	end
	-- NaN survives math.clamp and would poison the pivot, so reject it here.
	if x ~= x then
		return
	end

	-- Pointing wins over holding; otherwise the two would fight every frame.
	steerDir = 0

	local position = piece.pivot.Position
	local targetX = math.clamp(x, -Constants.STEER_LIMIT_X, Constants.STEER_LIMIT_X)
	piece.pivot = CFrame.new(targetX, position.Y, Constants.PLANE_Z) * piece.pivot.Rotation
	piece.model:PivotTo(piece.pivot)
end

function TowerService.spin(player: Player, clockwise: boolean)
	local piece = held
	if piece == nil or piece.player ~= player or state.phase ~= PHASE.AIMING then
		return
	end

	local turn = if clockwise then -math.pi / 2 else math.pi / 2
	piece.pivot = piece.pivot * CFrame.Angles(0, 0, turn)
	piece.model:PivotTo(piece.pivot)
end

-- Hand the piece to physics. Called by the holder, and by the turn loop when the
-- clock runs out or the holder leaves — hence no player check here.
function TowerService.release()
	local piece = held
	if piece == nil then
		return
	end
	held = nil
	steerDir = 0

	for _, part in piece.model:GetChildren() do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end
	table.insert(blocks, { model = piece.model, root = piece.root, settled = false })
	TowerStatsService.recordBlockPlaced(piece.player)

	state.phase = PHASE.SETTLING
	state.holderUserId = 0
	state.turnEndsAt = 0
	state.shapeId = 0
	broadcast()
end

local function beginTurn(player: Player)
	local shape = nextShape
	nextShape = Shapes.random()

	local model, root = buildPiece(shape)
	local pivot = spawnPivot()
	model:PivotTo(pivot)
	model.Parent = arena

	held = { model = model, root = root, shape = shape, pivot = pivot, player = player }
	-- A key still held from the previous turn must not carry over to the next
	-- player's piece.
	steerDir = 0

	state.phase = PHASE.AIMING
	state.holderUserId = player.UserId
	state.turnEndsAt = workspace:GetServerTimeNow() + Constants.TURN_SECONDS
	state.shapeId = shape.id
	state.nextShapeId = nextShape.id
	broadcast()
end

-- ---------------------------------------------------------------- the plane --

local function clampToPlane()
	for _, block in blocks do
		local root = block.root
		if root.Parent == nil then
			continue
		end

		local velocity = root.AssemblyLinearVelocity
		local spin = root.AssemblyAngularVelocity
		-- Skip assemblies that have gone to sleep; writing velocity to a resting
		-- part would wake it up every frame.
		if velocity.Magnitude < 0.05 and spin.Magnitude < 0.05 then
			continue
		end

		if velocity.Z ~= 0 then
			root.AssemblyLinearVelocity = Vector3.new(velocity.X, velocity.Y, 0)
		end
		-- Only in-plane spin (about Z) survives; tipping toward or away from the
		-- camera is what we're suppressing.
		if spin.X ~= 0 or spin.Y ~= 0 then
			root.AssemblyAngularVelocity = Vector3.new(0, 0, spin.Z)
		end

		-- Every cell of a piece shares one Z (pieces only ever rotate about Z), so
		-- the root's drift is the assembly's drift. Nudging the root drags the
		-- welded assembly with it; Model:PivotTo is no use here because a model's
		-- WorldPivot doesn't track parts the physics engine moved.
		local drift = root.Position.Z - Constants.PLANE_Z
		if math.abs(drift) > Constants.PLANE_TOLERANCE then
			root.CFrame = root.CFrame - Vector3.new(0, 0, drift)
		end
	end
end

-- Highest world-Y a part reaches, accounting for rotation: project each half
-- extent onto the world up axis. Blocks tip in-plane, so their bounding box is
-- rarely axis-aligned and `Position.Y + Size.Y / 2` would under-read a tilted
-- piece.
local function partTopY(part: BasePart): number
	local cf = part.CFrame
	local half = part.Size / 2
	local reach = math.abs(cf.RightVector.Y) * half.X
		+ math.abs(cf.UpVector.Y) * half.Y
		+ math.abs(cf.LookVector.Y) * half.Z
	return cf.Position.Y + reach
end

-- ---------------------------------------------------------------- the storm --
--
-- The pressure mechanic. Every stage names a height to beat before the clock
-- runs out; clearing it welds a permanent floor onto the tower at whatever
-- altitude the players got to, and sets a higher bar.

-- Anchored checkpoint platforms, tracked separately from `blocks` because they
-- have no physics but still count toward the tower's top.
local platforms: { BasePart } = {}

-- Everything the new platform replaces. The checkpoint spawns at the tower's
-- highest point, so every settled block is underneath it — but a piece dropped
-- a moment ago could still be falling *above* the line, and that one survives.
local function clearBlocksBelow(cutoffY: number)
	for index = #blocks, 1, -1 do
		local block = blocks[index]
		local highest = -math.huge
		for _, part in block.model:GetChildren() do
			if part:IsA("BasePart") then
				highest = math.max(highest, partTopY(part))
			end
		end
		if highest <= cutoffY then
			block.model:Destroy()
			table.remove(blocks, index)
		end
	end
end

local function spawnCheckpoint(topY: number)
	local full = Constants.PLATFORM_SIZE

	local part = Instance.new("Part")
	part.Name = `Checkpoint{#platforms + 1}`
	part.Anchored = true
	part.Material = Enum.Material.Neon
	part.Color = Constants.PLATFORM_SPAWN_COLOR
	part.CustomPhysicalProperties = Constants.BLOCK_PHYSICS
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	-- Enters as a sliver at the center line and stretches outward to full width;
	-- because the part is anchored, tweening Size grows it evenly about its
	-- position rather than dragging one face.
	part.Size = Vector3.new(0.5, full.Y, full.Z)
	part.Position = Vector3.new(0, topY + full.Y / 2, Constants.PLANE_Z)
	part.Parent = arena
	table.insert(platforms, part)

	-- The tower below is now scaffolding: the platform is the new ground, and
	-- keeping a few hundred settled parts alive under it buys nothing but
	-- physics cost. Height is measured off the platform's own top, so the
	-- readout doesn't move when they go.
	clearBlocksBelow(part.Position.Y - full.Y / 2)

	local grow = TweenService:Create(
		part,
		TweenInfo.new(Constants.PLATFORM_GROW_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = full }
	)
	grow:Play()

	grow.Completed:Connect(function()
		-- Still Neon while it fades, so it visibly cools from glowing white down
		-- to black instead of snapping to a matte part.
		local fade = TweenService:Create(
			part,
			TweenInfo.new(Constants.PLATFORM_FADE_SECONDS),
			{ Color = Constants.PLATFORM_SETTLED_COLOR }
		)
		fade:Play()
		fade.Completed:Connect(function()
			part.Material = Enum.Material.SmoothPlastic
		end)
	end)
end

-- Returns true when the stage changed and clients need to hear about it.
local function updateStorm(height: number): boolean
	local now = workspace:GetServerTimeNow()

	-- Nobody playing: hold the clock rather than letting it expire against an
	-- empty server.
	if #queue == 0 then
		state.stormEndsAt = now + Constants.STORM_SECONDS
		return false
	end

	if height >= state.targetHeight then
		spawnCheckpoint(baseTopY + height)
		state.checkpoints += 1
		-- The next bar is measured from what they actually reached, not from the
		-- target they just cleared, so overshooting doesn't make the next stage
		-- trivial.
		state.targetHeight = height + Constants.STORM_TARGET_STEP
		state.stormEndsAt = now + Constants.STORM_SECONDS
		return true
	end

	if now >= state.stormEndsAt then
		-- Ran out of time. For now the stage just restarts — see "Open design
		-- question" in docs/game/TowerGame.md before adding a punishment.
		state.stormEndsAt = now + Constants.STORM_SECONDS
		return true
	end

	return false
end

-- --------------------------------------------------------------- the height --

local function updateHeight()
	local top = baseTopY

	for index = #blocks, 1, -1 do
		local block = blocks[index]
		if block.root.Parent == nil then
			table.remove(blocks, index)
			continue
		end
		-- Knocked off the platform: stop paying for its physics.
		if block.root.Position.Y < baseTopY - Constants.DESPAWN_BELOW then
			block.model:Destroy()
			table.remove(blocks, index)
			continue
		end

		if not block.settled and block.root.AssemblyLinearVelocity.Magnitude < Constants.SETTLED_SPEED then
			block.settled = true
		end
		if not block.settled then
			continue
		end

		for _, part in block.model:GetChildren() do
			if not part:IsA("BasePart") then
				continue
			end
			local partTop = partTopY(part)
			if partTop > top then
				top = partTop
			end
		end
	end

	-- Checkpoint platforms are part of the tower even though they aren't blocks.
	for _, platform in platforms do
		local platformTop = partTopY(platform)
		if platformTop > top then
			top = platformTop
		end
	end

	local height = top - baseTopY
	local changed = math.abs(height - state.height) > Constants.HEIGHT_EPSILON or #blocks ~= state.blockCount
	state.height = height
	if height > state.maxHeight then
		state.maxHeight = height
		-- Everyone in the server shares the tower, so everyone gets credit for
		-- the record it just set.
		TowerStatsService.recordHeight(height)
	end

	if updateStorm(height) then
		changed = true
	end

	-- Re-send periodically even when nothing moved: a player who joined between
	-- broadcasts has no other way to learn the state.
	if changed or os.clock() - lastBroadcast > 1 then
		broadcast()
	end
end

-- ----------------------------------------------------------------- the turns --

local function nextPlayer(): Player?
	while #queue > 0 do
		local player = table.remove(queue, 1) :: Player
		if player.Parent ~= Players then
			continue
		end
		-- Back of the line, so the rotation is fair with any player count.
		table.insert(queue, player)
		return player
	end
	return nil
end

local function goIdle()
	if state.phase == PHASE.IDLE then
		return
	end
	state.phase = PHASE.IDLE
	state.holderUserId = 0
	state.turnEndsAt = 0
	state.shapeId = 0
	broadcast()
end

local function runTurns()
	while true do
		local player = nextPlayer()
		if player == nil then
			goIdle()
			task.wait(0.5)
			continue
		end

		beginTurn(player)

		-- Ends on any of: the player released it (held goes nil), the 20s clock
		-- expired, or the holder left mid-turn.
		while held ~= nil and workspace:GetServerTimeNow() < state.turnEndsAt and player.Parent == Players do
			task.wait(0.1)
		end
		if held ~= nil then
			TowerService.release()
		end

		task.wait(Constants.SETTLE_SECONDS)
	end
end

-- ----------------------------------------------------------------- lifecycle --

local function addPlayer(player: Player)
	table.insert(queue, player)
	-- With StreamingEnabled (the default for new places) the client only receives
	-- parts near its replication focus, and the focus normally comes from the
	-- character — which this game doesn't spawn. Without this the player sees a
	-- live HUD over an empty sky.
	if base then
		player.ReplicationFocus = base
	end
	-- The joiner's controller isn't listening yet; the 1s heartbeat in
	-- updateHeight is what actually gets them their first state.
	broadcast()
end

local function removePlayer(player: Player)
	local index = table.find(queue, player)
	if index then
		table.remove(queue, index)
	end
end

function TowerService.Start()
	if Constants.DISABLE_CHARACTERS then
		-- Stationary camera, no walking: an avatar would only be a physics prop
		-- standing under a falling tower.
		Players.CharacterAutoLoads = false
	end

	buildArena()
	state.stormEndsAt = workspace:GetServerTimeNow() + Constants.STORM_SECONDS

	Packets.Steer.listen(function(payload, player)
		TowerService.setSteer(player, payload.dir)
	end)
	Packets.Aim.listen(function(payload, player)
		TowerService.aim(player, payload.x)
	end)
	Packets.Spin.listen(function(payload, player)
		TowerService.spin(player, payload.clockwise)
	end)
	Packets.Release.listen(function(_payload, player)
		local piece = held
		if piece == nil or piece.player ~= player then
			return
		end
		TowerService.release()
	end)

	for _, player in Players:GetPlayers() do
		addPlayer(player)
	end
	Players.PlayerAdded:Connect(addPlayer)
	Players.PlayerRemoving:Connect(removePlayer)

	RunService.Heartbeat:Connect(function(deltaTime)
		stepHeld(deltaTime)
		clampToPlane()
	end)

	task.spawn(function()
		while true do
			task.wait(Constants.POLL_INTERVAL)
			updateHeight()
		end
	end)

	task.spawn(runTurns)
end

return TowerService
