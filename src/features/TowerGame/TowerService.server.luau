-- Authoritative core for TowerGame.
--
-- Note on reading this file: the sections are ordered by dependency, not by
-- importance. Luau locals are only visible below their definition, so anything
-- `beginTurn` or `release` calls has to appear above them.
--
-- Owns: the arena, the turn queue, the held piece, the dropped blocks, the
-- tower's height, and the storm stage. Clients send *intent* (steer / spin /
-- release) and this file decides whether it happens — the held piece is a
-- server-owned Model, so its movement replicates for free and every player
-- watches the same aim.
--
-- Aiming is split: the holder's client owns how it *feels* (it renders its own
-- preview and moves it at frame rate) and reports the resulting placement; this
-- file decides whether that placement is legal, and moves the real piece so
-- spectators see it. A placement is fully described by an X and a quarter-turn
-- count, so there is no "move left" — just "the piece is here now".
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

local BlockLabel = require(ReplicatedStorage.Features.TowerGame.BlockLabel)
local BlockSkins = require(ReplicatedStorage.Features.TowerGame.BlockSkins)
local BlockTypes = require(ReplicatedStorage.Features.TowerGame.BlockTypes)
local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)
local NoobBlock = require(ReplicatedStorage.Features.TowerGame.NoobBlock)
local Packets = require(ReplicatedStorage.Features.TowerGame.Packets)
local Sfx = require(ReplicatedStorage.Features.TowerGame.Sfx)
local Shapes = require(ReplicatedStorage.Features.TowerGame.Shapes)
local Zones = require(ReplicatedStorage.Features.TowerGame.Zones)

-- Server-realm siblings (ServerScriptService.Features.TowerGame.*).
local CashService = require(script.Parent.CashService)
local TowerStatsService = require(script.Parent.TowerStatsService)

type Block = {
	model: Model,
	root: BasePart,
	-- Only settled blocks count toward the height, so a piece still falling
	-- through the air can't spike the readout. Set by the poll, and taken back
	-- off a block that gets knocked loose again.
	settled: boolean,
	-- When the assembly first went quiet, or nil if it isn't. A block has to hold
	-- still for SETTLE_CONFIRM_SECONDS before `settled` follows — see updateHeight.
	slowSince: number?,
	-- Latch for the once-per-block half of settling (the settle sound).
	settledOnce: boolean,
	-- nil for a piece that brought its own model (the Noob).
	shape: Shapes.Shape?,
	skin: BlockSkins.Skin,
	blockType: BlockTypes.BlockType?,
	-- The colour every cell was painted, kept so effects that repaint the block
	-- (a bomb's flash, a burn's charring) can put it back or lerp from it.
	baseColor: Color3,
	-- True for a model this file didn't build out of cells. Those are excluded
	-- from the height, left out of the zone dressing, and only loosely held to
	-- the play plane — a Noob has to be allowed to turn around.
	custom: boolean,
	impactSound: Sound?,
	settleSound: Sound?,
	-- Speed carried into the current frame. Sampled before physics damps it, so
	-- a Touched handler can tell a landing from a nudge.
	speed: number,
	-- One-shot latch for the block type's effect.
	resolved: boolean,
	lastImpactAt: number,
	-- When this block caught fire, or nil if it hasn't. Burning is a state a
	-- block can be given by a neighbour, not just something the Burning type has.
	burnStartedAt: number?,
}

type Held = {
	model: Model,
	root: BasePart,
	shape: Shapes.Shape?,
	skin: BlockSkins.Skin,
	blockType: BlockTypes.BlockType?,
	baseColor: Color3,
	custom: boolean,
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
-- Reverse index into `blocks`, so a part found by a spatial query can be traced
-- back to the block that owns it without walking the list. Burning uses it to
-- find what it's resting against; keep it in step with every add and remove.
local blockByModel: { [Model]: Block } = {}
local held: Held? = nil
-- Distance to the next checkpoint. Grows by STORM_GAP_GROWTH every time one is
-- cleared, so each floor is a little further than the last.
local stormGap = Constants.STORM_FIRST_TARGET
-- Who dropped the piece that's currently settling. Whoever that is gets paid for
-- any height the tower gains, since they're the one who put it there.
local lastDropper: Player? = nil
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
	blockTypeId = 0,
	nextShapeId = nextShape.id,
	order = {},
	targetHeight = Constants.STORM_FIRST_TARGET,
	zoneBaseHeight = 0,
	stormEndsAt = 0,
	checkpoints = 0,
	zoneId = Zones.DEFAULT_ID,
	zoneSky = 1,
}

-- Direction the storm-zone wind is currently leaning, and when it next drifts.
local windDirection = 1
local windChangeAt = 0


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

-- Sounds live on the piece itself so they're positional and replicate with it —
-- the server calls :Play() and every client hears it from the right place.
local function attachSound(part: BasePart, name: string, soundId: string, volume: number): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = soundId
	sound.Volume = volume
	sound.RollOffMaxDistance = Constants.SOUND_RANGE
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.Parent = part
	return sound
end

-- A fresh colour per piece. Random hue at a fixed saturation and value, rather
-- than a random RGB triple, so every block is vivid and none come out muddy or
-- washed out against the sky.
local function randomColor(): Color3
	return Color3.fromHSV(math.random(), 0.68, 0.98)
end

-- Every BasePart of a model, descendants included. Pieces built here are flat
-- (cells are direct children), but a Noob rig hangs a Handle inside every
-- accessory, and an anchored hat on an unanchored rig floats where it was.
local function modelParts(model: Model): { BasePart }
	local found = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(found, descendant)
		end
	end
	return found
end

-- The name plate hanging off the piece: "Bomb T-Shape", or just "T-Shape" for an
-- ordinary block. Types with their own model have no silhouette to name.
local function labelPiece(model: Model, root: BasePart, shape: Shapes.Shape?, blockType: BlockTypes.BlockType?)
	local title = BlockLabel.titleFor(if blockType then blockType.name else nil, if shape then shape.name else nil)
	BlockLabel.attach(model, root, title, if blockType then blockType.description else nil)
end

local function buildPiece(shape: Shapes.Shape, skin: BlockSkins.Skin, blockType: BlockTypes.BlockType?): (Model, BasePart, Color3)
	local model = Instance.new("Model")
	model.Name = `Piece_{shape.name}`
	-- The skin keeps its material and its sounds; only the colour is rolled.
	local color = randomColor()

	local root: BasePart? = nil
	for index, cell in shape.cells do
		local part = Instance.new("Part")
		part.Name = `Cell{index}`
		part.Size = Vector3.new(Constants.BLOCK_SIZE, Constants.BLOCK_SIZE, Constants.BLOCK_DEPTH)
		part.Color = color
		part.Material = skin.material
		part.Transparency = skin.transparency or 0
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

	-- A special block has to be readable at a glance, and it can't repaint the
	-- piece to say so — the skin already owns the color. A Highlight sits on top
	-- of whatever look the skin picked.
	if blockType then
		local highlight = Instance.new("Highlight")
		highlight.Name = "TypeTell"
		highlight.FillColor = blockType.tell
		highlight.OutlineColor = blockType.tell
		highlight.FillTransparency = 0.65
		highlight.OutlineTransparency = 0
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Parent = model
	end

	-- Pivot at the bounding-box center so a quarter turn spins in place instead
	-- of swinging the piece around its first cell. Deliberately NO PrimaryPart:
	-- when one is set, `GetPivot`/`PivotTo` use that part's CFrame and ignore
	-- WorldPivot, which would put the rotation axis through the first cell.
	model.WorldPivot = model:GetBoundingBox()
	labelPiece(model, rootPart, shape, blockType)
	return model, rootPart, color
end

-- Where a fresh piece appears: clear of whatever has been built so far.
local function spawnPivot(): CFrame
	return CFrame.new(0, baseTopY + math.max(state.height, 0) + Constants.SPAWN_CLEARANCE, Constants.PLANE_Z)
end

-- ---------------------------------------------------------------- the zones --
--
-- The server owns the half of a zone that can't be faked client-side: how blocks
-- feel. The look (sky, weather particles, the warning) is TowerZoneController's
-- job — it reads the same zone id off the state packet.

local SURFACES = {
	"TopSurface",
	"BottomSurface",
	"LeftSurface",
	"RightSurface",
	"FrontSurface",
	"BackSurface",
}

local function setSurfaces(part: BasePart, surface: Enum.SurfaceType)
	for _, name in SURFACES do
		(part :: any)[name] = surface
	end
end

-- Retro dresses blocks in the old stud look — on every face, so a cube reads as
-- a 1962 brick from any angle instead of only from above. Glow blocks are
-- exempt: their whole point is the material, and studding them over would just
-- make them grey.
--
-- Leaving a zone undresses the block again, because a zone is a property of the
-- world rather than of whichever zone a block happened to spawn in.
-- What a block would feel like with no zone in play: bouncy blocks are the one
-- type that owns its own physics.
local function basePhysics(blockType: BlockTypes.BlockType?): PhysicalProperties
	if blockType and blockType.kind == "bouncy" then
		return Constants.BOUNCY_PHYSICS
	end
	return Constants.BLOCK_PHYSICS
end

local function applyZoneLook(model: Model, skin: BlockSkins.Skin, blockType: BlockTypes.BlockType?)
	-- A Noob isn't scenery. Studding one over, or handing it snow friction, turns
	-- a character back into a prop.
	if model:GetAttribute(Constants.RAW_MODEL_ATTRIBUTE) then
		return
	end

	local zone = Zones.get(state.zoneId)
	local retro = zone.kind == "retro" and skin.name ~= "Glow"

	for _, part in modelParts(model) do
		if retro then
			part.Material = Enum.Material.Plastic
			setSurfaces(part, Enum.SurfaceType.Studs)
		else
			part.Material = skin.material
			setSurfaces(part, Enum.SurfaceType.Smooth)
		end
		-- Snow wins over everything: a slippery zone is the whole point of it.
		part.CustomPhysicalProperties = if zone.kind == "snowy"
			then Constants.SNOWY_PHYSICS
			else basePhysics(blockType)
	end
end

-- Re-dress everything already standing when the zone changes, so a zone is a
-- property of the world rather than of whatever happened to spawn during it.
local function applyZoneToTower()
	-- Gravity is the one zone rule that isn't per-block: Space drops it to a
	-- sixth, everything else puts it back. Server-owned, so it replicates.
	workspace.Gravity = Zones.gravityOf(state.zoneId)

	for _, block in blocks do
		applyZoneLook(block.model, block.skin, block.blockType)
	end
	local piece = held
	if piece then
		applyZoneLook(piece.model, piece.skin, piece.blockType)
	end
end

-- A steady lean rather than a gale: enough to make a tall stack argue with
-- itself, not enough to sweep it off the platform. Applied as an impulse scaled
-- by mass so every block leans by the same acceleration regardless of size, and
-- so sleeping assemblies wake up and join in.
local function applyWind(deltaTime: number)
	if Zones.get(state.zoneId).kind ~= "stormy" then
		return
	end

	local now = os.clock()
	if now >= windChangeAt then
		windChangeAt = now + Constants.STORM_GUST_SECONDS
		windDirection = if math.random() < 0.5 then -1 else 1
	end

	local push = windDirection * Constants.STORM_WIND * deltaTime
	for _, block in blocks do
		local root = block.root
		if root.Parent == nil then
			continue
		end
		root:ApplyImpulse(Vector3.new(push * root.AssemblyMass, 0, 0))
	end
end

-- ------------------------------------------------------------ the placement --
--
-- One entry point. The holder's client says where the piece is; this decides
-- whether that's allowed. Everything a client can influence about a piece is
-- these two numbers, both clamped here, so "the client owns the feel" never
-- becomes "the client owns the game".

function TowerService.applyPlacement(player: Player, x: number, turns: number)
	local piece = held
	if piece == nil or piece.player ~= player or state.phase ~= PHASE.AIMING then
		return
	end
	-- NaN survives math.clamp and would poison the pivot, so reject it here.
	if x ~= x then
		return
	end

	local clampedX = math.clamp(x, -Constants.STEER_LIMIT_X, Constants.STEER_LIMIT_X)
	local quarter = math.floor(turns) % 4

	piece.pivot = CFrame.new(clampedX, piece.pivot.Position.Y, Constants.PLANE_Z)
		* CFrame.Angles(0, 0, -quarter * math.pi / 2)
	piece.model:PivotTo(piece.pivot)
end

-- -------------------------------------------------------------- the landing --

local function playImpact(block: Block, speed: number)
	local sound = block.impactSound
	if sound == nil then
		return
	end

	local now = os.clock()
	if now - block.lastImpactAt < Constants.IMPACT_COOLDOWN then
		return
	end
	block.lastImpactAt = now

	-- A gentle settle and a 60-stud drop should not sound the same.
	local loudness = math.clamp(
		(speed - Constants.IMPACT_MIN_SPEED) / (Constants.IMPACT_LOUD_SPEED - Constants.IMPACT_MIN_SPEED),
		0,
		1
	)
	local range = block.skin.pitchRange
	sound.Volume = block.skin.volume * (0.35 + 0.65 * loudness)
	sound.PlaybackSpeed = range[1] + math.random() * (range[2] - range[1])
	sound:Play()
end

-- Weld the block to everything it's resting against. Welding to an anchored
-- platform effectively anchors it, which is exactly what glue should feel like.
--
-- Fired when the block *settles*, not when it first touches something. At the
-- moment of impact a block is often still mid-bounce with nothing but the part
-- it just clipped nearby, so welding then glues it to whatever it happened to
-- graze on the way down. Waiting until it stops means the contacts we find are
-- the ones it's actually resting on.
local function glueBlock(block: Block)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { block.model }

	for _, part in block.model:GetChildren() do
		if not part:IsA("BasePart") then
			continue
		end
		local reach = part.Size + Vector3.one * Constants.GLUE_RADIUS
		for _, other in workspace:GetPartBoundsInBox(part.CFrame, reach, params) do
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = part
			weld.Part1 = other
			weld.Parent = part
		end
	end
end

local function detonateBlock(block: Block)
	local explosion = Instance.new("Explosion")
	explosion.Position = block.root.Position
	explosion.BlastRadius = Constants.EXPLOSION_RADIUS
	explosion.BlastPressure = Constants.EXPLOSION_PRESSURE
	-- Our pieces are held together by WeldConstraints, which an Explosion doesn't
	-- break — so this throws blocks around without dissolving them into cells.
	explosion.DestroyJointRadiusPercent = 0
	explosion.Parent = workspace

	-- BlastPressure alone barely shifts a welded assembly, so throw everything in
	-- radius by hand. Falls off with distance, so the blast has a shape rather
	-- than flinging the whole tower equally.
	local origin = explosion.Position
	for _, other in blocks do
		local root = other.root
		if root.Parent == nil or other == block then
			continue
		end
		local offset = root.Position - origin
		local distance = offset.Magnitude
		if distance > Constants.EXPLOSION_RADIUS then
			continue
		end
		local falloff = 1 - distance / Constants.EXPLOSION_RADIUS
		-- Bias upward so the tower erupts rather than being swept sideways.
		local direction = (offset.Unit + Vector3.new(0, 0.6, 0)).Unit
		root:ApplyImpulse(direction * Constants.EXPLOSION_IMPULSE * falloff * root.AssemblyMass)
	end

	-- On a throwaway marker rather than the block: the block is about to be
	-- destroyed, and a sound parented to it would go with it.
	Sfx.playAtPosition("Explosion", origin, Constants.EXPLOSION_VOLUME)
	block.model:Destroy()
end

local function paint(block: Block, color: Color3)
	for _, part in modelParts(block.model) do
		part.Color = color
	end
end

-- A bomb warns before it goes off: three red flashes and three beeps, then the
-- blast. The delay is the mechanic — it's long enough for the room to see which
-- block is about to erupt and short enough that nobody can build around it.
--
-- Every step re-checks that the block is still in the world, because a bomb can
-- easily be wiped by a checkpoint demolition or knocked off the edge mid-fuse.
local function armBomb(block: Block)
	task.spawn(function()
		for _ = 1, Constants.BOMB_BEEPS do
			if block.root.Parent == nil then
				return
			end
			paint(block, Constants.BOMB_FLASH_COLOR)
			Sfx.playAt("BombBeep", block.root)
			task.wait(Constants.BOMB_BEEP_ON)
			if block.root.Parent == nil then
				return
			end
			paint(block, block.baseColor)
			task.wait(Constants.BOMB_BEEP_OFF)
		end
		if block.root.Parent == nil then
			return
		end
		detonateBlock(block)
	end)
end

-- Catching fire is a *state*, not a type: the Burning block starts alight, and
-- anything it's resting against catches from it, so the hazard spreads through
-- the tower rather than staying with the piece that caused it.
local function igniteBlock(block: Block)
	-- A Noob would char and disintegrate like scenery, which reads as a bug
	-- rather than a joke.
	if block.burnStartedAt ~= nil or block.custom or block.root.Parent == nil then
		return
	end
	block.burnStartedAt = os.clock()

	local fire = Instance.new("Fire")
	fire.Name = "Burning"
	fire.Heat = 10
	fire.Size = Constants.BLOCK_SIZE * 1.5
	fire.Parent = block.root
end

-- Wire up what a block does when it hits something. The sound, the block type
-- and anything unlucky enough to be underneath all fire from the same signal,
-- because "it landed" is one event.
local function watchLanding(block: Block)
	local function onTouched(hit: BasePart)
		local speed = block.speed
		if speed < Constants.IMPACT_MIN_SPEED then
			return
		end

		playImpact(block, speed)

		-- Landing on a Noob is fatal to the Noob, whatever kind of block did it.
		local humanoid = NoobBlock.humanoidOf(hit)
		if humanoid and humanoid.Parent then
			NoobBlock.kill(humanoid.Parent :: Model)
		end

		-- Only bombs resolve on impact. Glue and Clone wait for the block to come
		-- to rest, which the height poll handles.
		if block.resolved or block.blockType == nil or block.blockType.kind ~= "explosion" then
			return
		end
		block.resolved = true
		armBomb(block)
	end

	for _, part in modelParts(block.model) do
		part.Touched:Connect(onTouched)
	end
end

-- The one place a live block enters the world. Called by `release` for the piece
-- the holder dropped, and by the Clone type for the copy it makes.
local function registerBlock(
	model: Model,
	root: BasePart,
	shape: Shapes.Shape?,
	skin: BlockSkins.Skin,
	blockType: BlockTypes.BlockType?,
	baseColor: Color3,
	custom: boolean
): Block
	local block: Block = {
		model = model,
		root = root,
		settled = false,
		slowSince = nil,
		settledOnce = false,
		shape = shape,
		skin = skin,
		blockType = blockType,
		baseColor = baseColor,
		custom = custom,
		impactSound = attachSound(root, "Impact", skin.impactSound, skin.volume),
		settleSound = if skin.settleSound
			then attachSound(root, "Settle", skin.settleSound, skin.volume * 0.6)
			else nil,
		speed = 0,
		resolved = false,
		lastImpactAt = 0,
		burnStartedAt = nil,
	}
	table.insert(blocks, block)
	blockByModel[model] = block
	watchLanding(block)

	-- A Burning block arrives already alight; everything else has to catch.
	if blockType and blockType.kind == "burning" then
		igniteBlock(block)
	end
	return block
end

-- Clone blocks: the copy drops in once the original has come to rest, from a
-- little above it and nudged to one side so it can't balance perfectly on its
-- parent. The copy is deliberately *plain* — a clone that cloned would bury the
-- arena inside two turns.
local function spawnCloneOf(block: Block)
	local shape = block.shape
	if shape == nil or block.root.Parent == nil then
		return
	end

	local model, root, color = buildPiece(shape, block.skin, nil)
	applyZoneLook(model, block.skin, nil)

	-- The block's own root, not the model's pivot: a model's WorldPivot doesn't
	-- track parts the physics engine moved, so the pivot is still wherever the
	-- piece was aimed.
	local origin = block.root.Position
	local drift = (if math.random() < 0.5 then -1 else 1) * Constants.CLONE_OFFSET_X
	model:PivotTo(CFrame.new(
		math.clamp(origin.X + drift, -Constants.STEER_LIMIT_X, Constants.STEER_LIMIT_X),
		origin.Y + Constants.CLONE_RISE,
		Constants.PLANE_Z
	))
	model.Parent = arena

	for _, part in modelParts(model) do
		part.Anchored = false
	end
	registerBlock(model, root, shape, block.skin, nil, color, false)
end

-- Burning spreads by contact, checked from the poll rather than from Touched:
-- a block already resting against its neighbour never fires Touched again, and
-- resting against something is exactly the case that should catch.
local function spreadBurn(block: Block)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { block.model }

	for _, part in modelParts(block.model) do
		local reach = part.Size + Vector3.one * Constants.BURN_SPREAD_RADIUS
		for _, other in workspace:GetPartBoundsInBox(part.CFrame, reach, params) do
			local model = other:FindFirstAncestorOfClass("Model")
			local neighbour = if model then blockByModel[model] else nil
			if neighbour then
				igniteBlock(neighbour)
			end
		end
	end
end

-- One step of a block's burn. Returns true when the block finished disintegrating
-- and the caller should drop it from the list.
local function tickBurn(block: Block, now: number): boolean
	local started = block.burnStartedAt
	if started == nil then
		return false
	end

	local progress = math.min((now - started) / Constants.BURN_SECONDS, 1)
	if progress >= 1 then
		block.model:Destroy()
		return true
	end

	-- Chars the whole way down, then goes to nothing over the last stretch, so
	-- there's a moment of "that one's about to go" before the hole appears.
	local charred = block.baseColor:Lerp(Color3.new(0, 0, 0), progress)
	local fadeFrom = 1 - Constants.BURN_FADE_FRACTION
	local fade = if progress > fadeFrom then (progress - fadeFrom) / Constants.BURN_FADE_FRACTION else 0
	local transparency = math.max(block.skin.transparency or 0, fade)
	for _, part in modelParts(block.model) do
		part.Color = charred
		part.Transparency = transparency
	end

	if now - started >= Constants.BURN_SPREAD_DELAY then
		spreadBurn(block)
	end
	return false
end

-- Hand the piece to physics. Called by the holder, and by the turn loop when the
-- clock runs out or the holder leaves — hence no player check here.
function TowerService.release()
	local piece = held
	if piece == nil then
		return
	end
	held = nil

	-- Stop advertising this piece as held. The holder's client finds "its" piece
	-- by this attribute, so leaving it set means every later turn re-finds this
	-- block instead of the new piece — it stays hidden and gets shadowed by the
	-- preview forever.
	piece.model:SetAttribute(Constants.HELD_ATTRIBUTE, nil)

	for _, part in modelParts(piece.model) do
		part.Anchored = false
	end

	registerBlock(piece.model, piece.root, piece.shape, piece.skin, piece.blockType, piece.baseColor, piece.custom)
	-- Everyone hears the drop from where it happened. The holder also gets their
	-- own confirmation cue locally (Drop2, played client-side).
	Sfx.playAt("Drop", piece.root)
	lastDropper = piece.player
	TowerStatsService.recordBlockPlaced(piece.player)

	state.phase = PHASE.SETTLING
	state.holderUserId = 0
	state.turnEndsAt = 0
	state.shapeId = 0
	state.blockTypeId = 0
	broadcast()
end

local function beginTurn(player: Player)
	local shape: Shapes.Shape? = nextShape
	nextShape = Shapes.random()

	-- Rolled per piece. Skin is pure flavour; type is the hazard, and it gets
	-- likelier the more floors the run has cleared.
	local skin = BlockSkins.random()
	local blockType = BlockTypes.roll(state.checkpoints)

	local model: Model?, root: BasePart?, color: Color3? = nil, nil, nil

	-- A type that overrides the model builds its own. That build can fail — the
	-- Noob rig is a Studio asset this file can't conjure — so a miss falls
	-- straight through to an ordinary tetromino rather than costing a turn.
	if blockType and blockType.overridesModel then
		model, root = NoobBlock.build()
		-- Nothing repaints a Noob, but every block carries the colour it started
		-- as, so the effects that do repaint have something to restore.
		color = Color3.new(1, 1, 1)
		if model == nil then
			blockType = nil
		end
	end

	if model == nil then
		shape = shape :: Shapes.Shape
		model, root, color = buildPiece(shape, skin, blockType)
	else
		-- No silhouette to name, so the plate is just the type.
		shape = nil
		labelPiece(model :: Model, root :: BasePart, nil, blockType)
	end

	local piece = model :: Model
	applyZoneLook(piece, skin, blockType)
	local pivot = spawnPivot()
	piece:PivotTo(pivot)
	-- Tells the holder's client "this one is yours" so it can hide the real piece
	-- and drive a local preview instead.
	piece:SetAttribute(Constants.HELD_ATTRIBUTE, player.UserId)
	piece.Parent = arena

	held = {
		model = piece,
		root = root :: BasePart,
		shape = shape,
		skin = skin,
		blockType = blockType,
		baseColor = color :: Color3,
		custom = shape == nil,
		pivot = pivot,
		player = player,
	}

	state.phase = PHASE.AIMING
	state.holderUserId = player.UserId
	state.turnEndsAt = workspace:GetServerTimeNow() + Constants.TURN_SECONDS
	-- 0 for a piece with no silhouette; the HUD names it from blockTypeId instead.
	state.shapeId = if shape then shape.id else 0
	state.blockTypeId = if blockType then blockType.id else 0
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

		-- Sampled before the collision damps it: Touched fires *after* physics has
		-- resolved the hit, so reading velocity there would report a block that has
		-- already stopped. This is the speed the impact sound is scaled by.
		block.speed = velocity.Magnitude

		-- Skip assemblies that have gone to sleep; writing velocity to a resting
		-- part would wake it up every frame.
		if velocity.Magnitude < 0.05 and spin.Magnitude < 0.05 then
			continue
		end

		if velocity.Z ~= 0 then
			root.AssemblyLinearVelocity = Vector3.new(velocity.X, velocity.Y, 0)
		end
		-- Only in-plane spin (about Z) survives; tipping toward or away from the
		-- camera is what we're suppressing. Custom models are exempt: a Noob turns
		-- about Y to face the way it's walking, and zeroing that would leave it
		-- moonwalking on the spot. It's still pinned to the plane by the Z terms.
		if not block.custom and (spin.X ~= 0 or spin.Y ~= 0) then
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

-- Drop a block out of the live list. Always through here: `blocks` and
-- `blockByModel` describe the same set and a stale entry in the map would hand
-- a burning neighbour a destroyed model.
local function removeBlockAt(index: number): Block
	local block = blocks[index]
	table.remove(blocks, index)
	blockByModel[block.model] = nil
	return block
end

local function highestPointOf(block: Block): number
	local highest = -math.huge
	for _, part in modelParts(block.model) do
		highest = math.max(highest, partTopY(part))
	end
	return highest
end

-- Everything the new platform replaces, thrown clear rather than deleted. The
-- checkpoint spawns at the tower's highest point, so every settled block is
-- underneath it — but a piece dropped a moment ago could still be falling
-- *above* the line, and that one survives.
--
-- The blocks are taken out of `blocks` immediately, which is what lets them
-- scatter in 3D: the plane clamp only holds on to live blocks.
local function blastBlocksBelow(cutoffY: number): { Block }
	local debris = {}
	for index = #blocks, 1, -1 do
		if highestPointOf(blocks[index]) > cutoffY then
			continue
		end
		local block = removeBlockAt(index)
		table.insert(debris, block)

		local root = block.root
		if root.Parent == nil then
			continue
		end
		root.AssemblyLinearVelocity = Vector3.new(
			(math.random() * 2 - 1) * Constants.CHECKPOINT_BLAST_HORIZONTAL,
			Constants.CHECKPOINT_BLAST_UP * (0.5 + math.random()),
			(math.random() * 2 - 1) * Constants.CHECKPOINT_BLAST_HORIZONTAL * 0.5
		)
		root.AssemblyAngularVelocity = Vector3.new(
			(math.random() * 2 - 1) * Constants.CHECKPOINT_BLAST_SPIN,
			(math.random() * 2 - 1) * Constants.CHECKPOINT_BLAST_SPIN,
			(math.random() * 2 - 1) * Constants.CHECKPOINT_BLAST_SPIN
		)
	end
	return debris
end

local function spawnCheckpoint(topY: number): BasePart
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

	return part
end

-- The storm arrives. Everything the players built gets thrown off the plane and
-- the run starts over from the base — no checkpoints, first target, fresh clock.
--
-- The debris is left to fly for a moment before cleanup rather than blinking
-- out, because the tower coming apart is the whole point of the deadline.
local function breakTower()
	local debris = blocks
	blocks = {}
	table.clear(blockByModel)

	for _, block in debris do
		local root = block.root
		if root.Parent == nil then
			continue
		end
		-- Out of the play plane on purpose: this is the one moment the game stops
		-- being 2D, so the wreck scatters instead of sliding sideways.
		local shove = Vector3.new(
			(math.random() * 2 - 1) * Constants.STORM_BLAST_HORIZONTAL,
			Constants.STORM_BLAST_UP * (0.6 + math.random() * 0.8),
			(math.random() * 2 - 1) * Constants.STORM_BLAST_HORIZONTAL * 0.5
		)
		root.AssemblyLinearVelocity = shove
		root.AssemblyAngularVelocity = Vector3.new(
			(math.random() * 2 - 1) * Constants.STORM_BLAST_SPIN,
			(math.random() * 2 - 1) * Constants.STORM_BLAST_SPIN,
			(math.random() * 2 - 1) * Constants.STORM_BLAST_SPIN
		)
	end

	for _, platform in platforms do
		platform:Destroy()
	end
	table.clear(platforms)

	task.delay(Constants.STORM_BLAST_SECONDS, function()
		for _, block in debris do
			block.model:Destroy()
		end
	end)
end

local function resetRun()
	breakTower()

	stormGap = Constants.STORM_FIRST_TARGET
	state.checkpoints = 0
	state.height = 0
	state.zoneBaseHeight = 0
	state.targetHeight = Constants.STORM_FIRST_TARGET
	-- Back to clear skies; a fresh run shouldn't inherit the last one's weather —
	-- or its gravity.
	state.zoneId = Zones.DEFAULT_ID
	state.zoneSky = math.random(1, 255)
	workspace.Gravity = Zones.gravityOf(state.zoneId)
	state.stormEndsAt = workspace:GetServerTimeNow() + Constants.STORM_SECONDS
	-- maxHeight deliberately survives: it's the server's best-ever record, not
	-- part of the run, and TowerStatsService has already banked it per player.
end

-- ----------------------------------------------------------- the checkpoint --
--
-- Clearing a stage is a cutscene, not a counter. Play stops, the camera pulls
-- back to take in the whole leg the players built, the new floor snaps in, the
-- scaffolding under it is blown apart, and only then does the queue start again.
--
-- While this is running `checkpointActive` freezes everything else: the turn
-- loop parks, and the height poll returns early so the debris flying past can't
-- be mistaken for a tower. The stage numbers are deliberately *not* advanced
-- until the end, because `zoneBaseHeight` and `height` are exactly the pair the
-- client camera frames the wide shot from — moving them early would collapse the
-- shot to nothing.

local checkpointActive = false

-- The holder loses the piece rather than the turn being played out under a
-- camera that's looking somewhere else. Their client sees the turn end and tears
-- its preview down on its own.
local function cancelHeldPiece()
	local piece = held
	if piece == nil then
		return
	end
	held = nil
	piece.model:Destroy()
	state.holderUserId = 0
	state.turnEndsAt = 0
	state.shapeId = 0
	state.blockTypeId = 0
end

local function runCheckpoint(height: number)
	checkpointActive = true
	cancelHeldPiece()
	state.phase = PHASE.CHECKPOINT
	broadcast()

	task.spawn(function()
		-- A beat of stillness, then the camera has its look.
		task.wait(Constants.CHECKPOINT_PAUSE_SECONDS + Constants.CHECKPOINT_VIEW_SECONDS)

		local platform = spawnCheckpoint(baseTopY + height)
		task.wait(Constants.PLATFORM_GROW_SECONDS)

		-- The tower below is scaffolding now: the platform is the new ground, and
		-- keeping a few hundred settled parts alive under it buys nothing but
		-- physics cost. Height is measured off the platform's own top, so the
		-- readout doesn't move when they go.
		local cutoff = platform.Position.Y - Constants.PLATFORM_SIZE.Y / 2
		local debris = blastBlocksBelow(cutoff)
		Sfx.playAtPosition("Explosion", Vector3.new(0, cutoff, Constants.PLANE_Z), Constants.EXPLOSION_VOLUME)

		task.wait(Constants.CHECKPOINT_BLAST_SECONDS)
		for _, block in debris do
			block.model:Destroy()
		end

		-- Only now does the stage actually advance.
		state.checkpoints += 1

		-- Clearing a checkpoint is what moves the run into a new zone.
		local zone = Zones.random(state.zoneId)
		state.zoneId = zone.id
		state.zoneSky = math.random(1, 255)
		applyZoneToTower()
		CashService.awardZone()

		-- Each floor is a little further out than the last.
		stormGap += Constants.STORM_GAP_GROWTH
		-- The next bar is measured from what they actually reached, not from the
		-- target they just cleared, so overshooting doesn't make the next stage
		-- trivial. That reached height is also where the progress line now
		-- starts from.
		state.zoneBaseHeight = height
		state.targetHeight = height + stormGap
		state.stormEndsAt = workspace:GetServerTimeNow() + Constants.STORM_SECONDS
		state.phase = PHASE.SETTLING
		broadcast()

		-- The camera is on its way back in; let it land before a piece appears.
		task.wait(Constants.CHECKPOINT_RESUME_SECONDS)
		checkpointActive = false
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
		runCheckpoint(height)
		return true
	end

	if now >= state.stormEndsAt then
		resetRun()
		return true
	end

	return false
end

-- --------------------------------------------------------------- the height --

-- What a block does the moment it comes to rest. Everything here is once-only:
-- a block that gets knocked loose and re-settles must not glue itself twice or
-- hand the players a second clone.
local function onSettled(block: Block)
	if not block.settledOnce then
		block.settledOnce = true
		-- The squishy skins get a second beat as they come to rest — the release
		-- half of the ASMR kit's press/release pair.
		if block.settleSound then
			block.settleSound:Play()
		end
		-- The plate has done its job: it named the piece while it mattered. A
		-- fifty-block tower wearing fifty of them is a wall of text.
		BlockLabel.dismiss(block.model)
	end

	-- A Noob stops being cargo and starts being a character. Once only: it walks,
	-- which un-settles it, and every re-settle would otherwise start a second
	-- wander loop fighting the first.
	if block.custom then
		if not block.resolved then
			block.resolved = true
			NoobBlock.activate(block.model)
		end
		return
	end

	local blockType = block.blockType
	if block.resolved or blockType == nil then
		return
	end

	-- Glue sets where the block ends up, not where it first grazed. Clone waits
	-- for the same moment, so the copy has something solid to land on.
	if blockType.kind == "glue" then
		block.resolved = true
		glueBlock(block)
	elseif blockType.kind == "clone" then
		block.resolved = true
		spawnCloneOf(block)
	end
end

-- Settling is a *sustained* state, not an instant. A block only counts toward
-- the tower once it has held still for SETTLE_CONFIRM_SECONDS, because a block
-- thrown up by a bomb is briefly motionless at the top of its arc — and a block
-- that is briefly motionless in mid-air used to be enough to clear a checkpoint
-- the players hadn't built to.
local function updateSettle(block: Block, now: number)
	local root = block.root
	local speed = root.AssemblyLinearVelocity.Magnitude
	local spin = root.AssemblyAngularVelocity.Magnitude

	if speed < Constants.SETTLED_SPEED and spin < Constants.SETTLED_SPIN then
		block.slowSince = block.slowSince or now
	else
		block.slowSince = nil
		-- Knocked properly loose: it stops counting until it comes to rest again.
		if speed > Constants.UNSETTLE_SPEED or spin > Constants.UNSETTLE_SPIN then
			block.settled = false
		end
	end

	local since = block.slowSince
	if block.settled or since == nil or now - since < Constants.SETTLE_CONFIRM_SECONDS then
		return
	end
	block.settled = true
	onSettled(block)
end

local function updateHeight()
	-- The checkpoint cutscene owns the world while it runs. Measuring a tower
	-- that's mid-demolition would spike the readout off flying debris and could
	-- clear the next stage from the wreckage of the last one.
	if checkpointActive then
		if os.clock() - lastBroadcast > 1 then
			broadcast()
		end
		return
	end

	local top = baseTopY
	local now = os.clock()

	for index = #blocks, 1, -1 do
		local block = blocks[index]
		if block.root.Parent == nil then
			removeBlockAt(index)
			continue
		end
		-- Knocked off the platform: stop paying for its physics.
		if block.root.Position.Y < baseTopY - Constants.DESPAWN_BELOW then
			removeBlockAt(index).model:Destroy()
			continue
		end
		-- Burning blocks char, spread, and eventually aren't there any more.
		if tickBurn(block, now) then
			removeBlockAt(index)
			continue
		end

		updateSettle(block, now)
		-- A Noob walks and jumps; it's a hazard standing on the tower, not part
		-- of it, and letting it into the measurement would make the height bob.
		if not block.settled or block.custom then
			continue
		end

		for _, part in modelParts(block.model) do
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
		-- Whoever placed last is the one who pushed it up, so they're paid for
		-- the studs gained. The record itself is shared — everyone in the server
		-- is building the same tower.
		local gained = height - state.maxHeight
		state.maxHeight = height
		TowerStatsService.recordHeight(height)

		local climber = lastDropper
		if climber and climber.Parent == Players then
			CashService.award(climber, math.floor(gained * Constants.CASH_PER_STUD))
		end
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
	state.blockTypeId = 0
	broadcast()
end

local function runTurns()
	while true do
		-- Nobody gets a piece while the checkpoint cutscene is playing.
		while checkpointActive do
			task.wait(0.1)
		end

		local player = nextPlayer()
		if player == nil then
			goIdle()
			task.wait(0.5)
			continue
		end

		beginTurn(player)

		-- Ends on any of: the player released it (held goes nil), the 20s clock
		-- expired, the holder left mid-turn, or a checkpoint took the piece away.
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
	-- Zones own gravity (Space drops it to a sixth), so the run starts from the
	-- default rather than from whatever the place file was saved with.
	workspace.Gravity = Zones.gravityOf(state.zoneId)
	state.stormEndsAt = workspace:GetServerTimeNow() + Constants.STORM_SECONDS

	Packets.Place.listen(function(payload, player)
		TowerService.applyPlacement(player, payload.x, payload.turns)
	end)
	Packets.Release.listen(function(payload, player)
		local piece = held
		if piece == nil or piece.player ~= player then
			return
		end
		-- The drop carries its own placement so the piece falls exactly where the
		-- holder saw it, even if their last Place packet is still in flight.
		TowerService.applyPlacement(player, payload.x, payload.turns)
		TowerService.release()
	end)

	for _, player in Players:GetPlayers() do
		addPlayer(player)
	end
	Players.PlayerAdded:Connect(addPlayer)
	Players.PlayerRemoving:Connect(removePlayer)

	RunService.Heartbeat:Connect(function(deltaTime)
		applyWind(deltaTime)
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
