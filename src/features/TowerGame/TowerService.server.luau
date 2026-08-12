-- Authoritative core for TowerGame.
--
-- Owns: the arena, the turn queue, the held piece, the dropped blocks, and the
-- tower's height. Clients send *intent* (steer / spin / release) and this file
-- decides whether it happens — the held piece is a server-owned Model, so its
-- movement replicates for free and every player watches the same aim.
--
-- The whole game runs on one Z slice (Constants.PLANE_Z). Roblox has no 2D
-- physics mode, so `clampToPlane` zeroes out-of-plane velocity every frame and
-- nudges back any block that still drifts. Pieces then tip and topple in-plane
-- like Tricky Towers instead of scattering into a 3D pile.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)
local Packets = require(ReplicatedStorage.Features.TowerGame.Packets)
local Shapes = require(ReplicatedStorage.Features.TowerGame.Shapes)

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
	queueCount = 0,
}

local function broadcast()
	state.blockCount = #blocks
	state.queueCount = #queue
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
	part.Size = Constants.BASE_SIZE
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

function TowerService.steer(player: Player, dir: number)
	local piece = held
	if piece == nil or piece.player ~= player or state.phase ~= PHASE.AIMING then
		return
	end
	-- Direction is a sign, not a distance — a client can't ask for a 50-stud step.
	local step = if dir < 0 then -Constants.BLOCK_SIZE else Constants.BLOCK_SIZE
	local targetX = piece.pivot.Position.X + step
	if math.abs(targetX) > Constants.STEER_LIMIT_X then
		return
	end

	piece.pivot = CFrame.new(targetX, piece.pivot.Position.Y, Constants.PLANE_Z) * piece.pivot.Rotation
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

	for _, part in piece.model:GetChildren() do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end
	table.insert(blocks, { model = piece.model, root = piece.root, settled = false })

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

-- --------------------------------------------------------------- the height --

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

	local height = top - baseTopY
	local changed = math.abs(height - state.height) > Constants.HEIGHT_EPSILON or #blocks ~= state.blockCount
	state.height = height
	if height > state.maxHeight then
		state.maxHeight = height
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

	Packets.Steer.listen(function(payload, player)
		TowerService.steer(player, payload.dir)
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

	RunService.Heartbeat:Connect(clampToPlane)

	task.spawn(function()
		while true do
			task.wait(Constants.POLL_INTERVAL)
			updateHeight()
		end
	end)

	task.spawn(runTurns)
end

return TowerService
