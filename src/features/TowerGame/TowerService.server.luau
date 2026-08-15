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
local Gamemodes = require(ReplicatedStorage.Features.TowerGame.Gamemodes)
local NoobBlock = require(ReplicatedStorage.Features.TowerGame.NoobBlock)
local Packets = require(ReplicatedStorage.Features.TowerGame.Packets)
local Sfx = require(ReplicatedStorage.Features.TowerGame.Sfx)
local Shapes = require(ReplicatedStorage.Features.TowerGame.Shapes)
local SkinPacks = require(ReplicatedStorage.Features.TowerGame.SkinPacks)
local Zones = require(ReplicatedStorage.Features.TowerGame.Zones)

-- Server-realm siblings (ServerScriptService.Features.TowerGame.*).
local CashService = require(script.Parent.CashService)
local TowerStatsService = require(script.Parent.TowerStatsService)

-- Whose skin pack is on the piece. Read once per turn, on the server, so the
-- block everyone sees carries the look its placer paid for.
local StoreService = require(script.Parent.Parent.Store.StoreService)
-- The "Not playing" toggle. Read here rather than trusted from the client: a
-- setting that changes whose turn it is has to be the server's answer.
local SettingsService = require(script.Parent.Parent.Settings.SettingsService)

-- The between-stages vote. TowerGame is the consumer here: GamemodeVote owns the
-- poll and knows nothing about towers, TowerGame owns the modes (Gamemodes.luau,
-- registered through Gamemode.luau) and decides when to ask.
local GamemodeVoteService = require(script.Parent.Parent.GamemodeVote.GamemodeVoteService)

-- Telemetry. Every call here is fire-and-forget and every one of them is a
-- no-op when the feature is switched off, so none of the code below has to
-- guard its reporting — see docs/game/Analytics.md.
local AnalyticsService = require(script.Parent.Parent.Analytics.AnalyticsService)

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
	-- The skin pack the placer had equipped, or nil if they had none. Overrides
	-- the rolled skin's material and outranks the zone's dressing, and it lives
	-- on the block rather than on the viewer — see `applyZoneLook`.
	pack: SkinPacks.SkinPack?,
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
	-- True once a Crate has been broken open. The cells are no longer one welded
	-- assembly, so the plane clamp has to hold each of them to the plane
	-- separately instead of steering the whole piece by its root.
	shattered: boolean,
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
	pack: SkinPacks.SkinPack?,
	blockType: BlockTypes.BlockType?,
	baseColor: Color3,
	custom: boolean,
	pivot: CFrame,
	-- Half the piece's tallest possible extent, i.e. how far below the pivot its
	-- lowest cell can reach at *any* of the four quarter turns. The spawn and the
	-- mid-turn lift both clear the tower by this plus SPAWN_CLEARANCE.
	halfHeight: number,
	-- What every part's CanCollide was before the piece was suspended, so `release`
	-- can put each one back instead of blanket-setting true.
	collision: { [BasePart]: boolean },
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
-- Set while a Double Turn owner has another piece coming, with how many are
-- left. Held as a separate slot rather than by pushing them onto the queue
-- twice, because the queue *is* the rotation — a duplicate entry there would
-- move everyone else's place in it. See `takeRepeatTurn`.
local repeatTurnFor: Player? = nil
local repeatTurnsLeft = 0
local blocks: { Block } = {}
-- Reverse index into `blocks`, so a part found by a spatial query can be traced
-- back to the block that owns it without walking the list. Burning uses it to
-- find what it's resting against; keep it in step with every add and remove.
local blockByModel: { [Model]: Block } = {}
-- Anchored checkpoint platforms, tracked separately from `blocks` because they
-- have no physics but still count toward the tower's top.
local platforms: { BasePart } = {}
local held: Held? = nil
-- Distance to the next checkpoint. Grows by STORM_GAP_GROWTH every time one is
-- cleared, so each floor is a little further than the last.
local stormGap = Constants.STORM_FIRST_TARGET
-- One-shot override for the next piece's type/skin, set by the "block" cmdr
-- command. Consumed (and reset) the moment `beginTurn` reads it, so it only
-- ever affects the very next piece rather than sticking around.
local blockTypeForced = false
local forcedBlockType: BlockTypes.BlockType? = nil
local skinForced = false
local forcedSkin: BlockSkins.Skin? = nil
-- Who dropped the piece that's currently settling. Whoever that is gets paid for
-- any height the tower gains, since they're the one who put it there.
local lastDropper: Player? = nil
-- Who dropped each block still in the world, for telemetry only. `lastDropper`
-- can't answer this: a block settles a second or two after it lands, by which
-- time the next player has usually been handed a piece and dropped it too.
--
-- Weak-keyed, so it holds nothing alive and needs no cleanup pass. A block's
-- model is destroyed by a blast, a checkpoint demolition or the storm, and the
-- entry goes with it on the next collection — the alternative is a table that
-- has to be pruned from six different teardown paths, one of which will
-- eventually be missed.
local placerOf: { [Model]: Player } = setmetatable({}, { __mode = "k" }) :: any
local nextShape: Shapes.Shape = Shapes.random()
local lastBroadcast = 0

-- Mirrors the State packet exactly; `broadcast` ships it as-is.
local state = {
	phase = PHASE.IDLE,
	holderUserId = 0,
	turnEndsAt = 0,
	height = 0,
	maxHeight = 0,
	pieceTop = 0,
	blockCount = 0,
	shapeId = 0,
	blockTypeId = 0,
	nextShapeId = nextShape.id,
	order = {},
	repeatUserId = 0,
	targetHeight = Constants.STORM_FIRST_TARGET,
	zoneBaseHeight = 0,
	stormEndsAt = 0,
	checkpoints = 0,
	zoneId = Zones.DEFAULT_ID,
	zoneSky = 1,
	-- The stage's clocks, broadcast rather than read from Constants on the
	-- client: a gamemode can change them, and the HUD's turn ring and storm bar
	-- are both fractions of these.
	turnSeconds = Gamemodes.DEFAULT.turnSeconds,
	stormSeconds = Gamemodes.DEFAULT.stormSeconds,
}

-- How the stage now being played was voted to behave. Set from the winner of the
-- between-stages vote (see runCheckpoint) and back to DEFAULT on a fresh run.
local stage: Gamemodes.Modifier = Gamemodes.DEFAULT

-- Switch the rules the stage is played by. The two clocks are mirrored into
-- `state` because the HUD draws them as fractions — a turn ring against the turn
-- length, the storm bar against the stage length — and a client reading those off
-- Constants would draw the wrong shape for every voted stage.
local function applyStage(modifier: Gamemodes.Modifier)
	stage = modifier
	state.turnSeconds = modifier.turnSeconds
	state.stormSeconds = modifier.stormSeconds
end

-- The Stormy zone's lightning. `nextStrikeAt` is when the next bolt is due;
-- `pendingStrikeX` is the column already announced by a red marker, nil while
-- none is, and `strikeDueAt` is when that one lands. Only the X is held: what it
-- hits is whatever is highest in that column when the bolt actually falls.
local nextStrikeAt = 0
local pendingStrikeX: number? = nil
local strikeDueAt = 0

-- Whether a player has opted out of taking turns.
--
-- The "more than one player" rule is the whole reason this isn't just a settings
-- read: a lone player who left the toggle on would sit watching an empty arena
-- with no way to work out why nothing was happening. With company, sitting out
-- is a real choice; alone, it's a soft-lock, so the setting is ignored.
local function isSpectating(player: Player): boolean
	if #Players:GetPlayers() <= 1 then
		return false
	end
	return SettingsService.get(player, Constants.SETTING_NOT_PLAYING) == true
end

-- Turn order for the HUD: whoever holds the piece first, then the queue in the
-- order they'll play. `queue` already rotates the holder to the back on their
-- turn, so the tail of this list is the player who went immediately before.
--
-- Spectators are left out. They keep their place in `queue` — the setting takes
-- them out of the turn order, not the room — but a headshot sitting in the strip
-- for someone who never gets a piece is the strip lying about what happens next.
local function buildOrder(): { number }
	local order = {}
	if state.holderUserId ~= 0 then
		table.insert(order, state.holderUserId)
	end
	for _, player in queue do
		if player.UserId ~= state.holderUserId and not isSpectating(player) then
			table.insert(order, player.UserId)
		end
	end
	return order
end

local function broadcast()
	state.blockCount = #blocks
	state.order = buildOrder()
	-- Whoever goes again after the current turn. The strip badges that player
	-- instead of listing them twice: `order` is keyed by user id on the client,
	-- and a duplicate id there is the same player, not a second slot.
	state.repeatUserId = if repeatTurnFor then repeatTurnFor.UserId else 0
	lastBroadcast = os.clock()
	Packets.State.sendToAll(state)
end

-- ------------------------------------------------------------------ telemetry --
--
-- The round and stage funnels measure something the room does together, not
-- something a player does, so every step in them is reported for everyone
-- present rather than for whoever happened to trigger it. A checkpoint cleared
-- by one player's block is a checkpoint all of them reached.
--
-- These are gathered here rather than inlined so the reporting reads as one
-- thing with one set of rules, and so the sequences below (which are already
-- long) gain a line each instead of five.

-- Which round-funnel steps exist. A step per checkpoint would be a hundred
-- steps and a funnel Roblox won't render; these are the depths worth asking
-- about, and `roundStepFor` maps a count onto the nearest one at or below it.
local ROUND_MILESTONES = { 1, 2, 3, 5, 10 }

local function roundStepFor(checkpoints: number): string?
	local best: number? = nil
	for _, milestone in ROUND_MILESTONES do
		if checkpoints >= milestone then
			best = milestone
		end
	end
	return if best then `Checkpoint {best}` else nil
end

-- Everyone in the server, including spectators. Deliberately not `queue`: a
-- player who has "Not playing" on is still watching the round happen, and
-- dropping them would quietly make every round funnel a survey of active
-- builders only.
local function reportAll(fn: (Player) -> ())
	for _, player in Players:GetPlayers() do
		fn(player)
	end
end

-- How far up the current stage the tower has been reported as getting. Reset
-- whenever a stage begins; see `reportStageProgress` for why it's a high-water
-- mark rather than a set.
local STAGE_MARKS = {
	{ at = 0.25, name = "25% Height" },
	{ at = 0.5, name = "50% Height" },
	{ at = 0.75, name = "75% Height" },
}
local stageMarksFired = 0

-- A fresh round: new funnel sessions for both the round and its first stage,
-- and the start of the progression path.
local function reportRoundStarted()
	stageMarksFired = 0
	reportAll(function(player)
		AnalyticsService.start(player, "round", "Round Started")
		AnalyticsService.start(player, "stage", "Stage Started")
		-- Closes the vote funnel opened before this round — the poll's payoff is
		-- that a round actually followed it.
		AnalyticsService.step(player, "vote", "Round Started")
		AnalyticsService.progression(player, "start", 1, "Checkpoint 1")
	end)
end

-- A stage cleared. The round funnel only moves on milestone checkpoints; the
-- stage funnel closes and reopens on every one.
local function reportStageCleared(checkpoints: number)
	stageMarksFired = 0
	local milestone = roundStepFor(checkpoints)
	reportAll(function(player)
		AnalyticsService.step(player, "stage", "Cleared")
		if milestone then
			AnalyticsService.step(player, "round", milestone)
		end
		AnalyticsService.progression(player, "complete", checkpoints, `Checkpoint {checkpoints}`)
		AnalyticsService.onboarding(player, 4)
		-- The next stage is a new attempt, so it gets its own session rather
		-- than more steps on the one just finished.
		AnalyticsService.start(player, "stage", "Stage Started")
	end)
end

-- How far the tower has climbed toward the current target, reported once per
-- mark passed. Called from the height poll, which runs five times a second, so
-- the high-water mark is checked here rather than leaning on the funnel's own
-- dedupe — that would work, but it would mean a `reportAll` over the whole
-- server on every poll to discover there was nothing to say.
--
-- Marks only ever fire upward. A tower that reaches 50% and is then gutted by a
-- bomb back to 20% has still reached 50% this stage, and re-firing the mark on
-- the way back up would count the same stage twice.
local function reportStageProgress(height: number)
	if stageMarksFired >= #STAGE_MARKS then
		return
	end

	local floor = state.zoneBaseHeight
	local span = state.targetHeight - floor
	if span <= 0 then
		return
	end
	local fraction = (height - floor) / span

	for index = stageMarksFired + 1, #STAGE_MARKS do
		local mark = STAGE_MARKS[index]
		if fraction < mark.at then
			break
		end
		stageMarksFired = index
		reportAll(function(player)
			AnalyticsService.step(player, "stage", mark.name)
		end)
	end
end

-- The storm took the tower. The round funnel simply stops where it got to —
-- that unfinished session is the drop-off the funnel exists to show — so the
-- only thing logged is the progression failure, at the depth they died on.
local function reportRoundLost(checkpoints: number)
	stageMarksFired = 0
	reportAll(function(player)
		AnalyticsService.progression(player, "fail", checkpoints + 1, `Checkpoint {checkpoints + 1}`)
		AnalyticsService.endSession(player, "round")
		AnalyticsService.endSession(player, "stage")
	end)
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

-- Where streaming is centred, for every player at once.
--
-- With StreamingEnabled a client is only sent parts within
-- `StreamingTargetRadius` (1024 studs by default) of its replication focus. This
-- game spawns no characters, so there's no focus unless the server names one —
-- and naming the *base* meant the sphere never moved: once the tower climbed
-- past the radius the blocks at the top stopped being replicated at all and the
-- players were building into an empty sky.
--
-- So the focus rides the tower instead. One shared invisible part is enough
-- because everyone is looking at the same tower; `updateStreamingFocus` keeps it
-- at the middle of the *live* span, which is the whole of what exists — every
-- checkpoint demolishes the floors below it, so the distance from the current
-- ground to the top is one stage's climb rather than the run's total altitude.
local streamingFocus: BasePart? = nil

local function buildStreamingFocus(): BasePart
	local part = Instance.new("Part")
	part.Name = "StreamingFocus"
	part.Anchored = true
	part.CanCollide = false
	-- Invisible to raycasts as well as to the eye: the landing preview casts
	-- straight down the play plane, and a marker sitting in it would read as a
	-- surface the piece could land on.
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.one
	part.Position = Vector3.new(0, baseTopY, Constants.PLANE_Z)
	part.Parent = arena
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

	streamingFocus = buildStreamingFocus()
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

-- Take a piece out of the physics world for as long as the holder is aiming it.
--
-- Anchored is *not* enough on its own: an anchored, colliding part is immovable
-- world geometry, so a piece parked over the tower wedges or shoves whatever is
-- still settling underneath it. That's how a placement could wreck the tower
-- before it had even been dropped.
--
-- Returns what each part's CanCollide was so `release` can put it back one part
-- at a time, rather than blanket-setting true — a Noob rig arrives with its own
-- answer per limb and accessory, and handing a hat collision makes it a prop
-- that knocks blocks over.
local function suspendCollision(model: Model): { [BasePart]: boolean }
	local saved = {}
	for _, part in modelParts(model) do
		saved[part] = part.CanCollide
		part.CanCollide = false
	end
	return saved
end

local function restoreCollision(model: Model, saved: { [BasePart]: boolean })
	for _, part in modelParts(model) do
		local was = saved[part]
		part.CanCollide = if was ~= nil then was else true
	end
end

-- The name plate hanging off the piece: "Bomb T-Shape", or just "T-Shape" for an
-- ordinary block. Types with their own model have no silhouette to name.
local function labelPiece(model: Model, root: BasePart, shape: Shapes.Shape?, blockType: BlockTypes.BlockType?)
	local title = BlockLabel.titleFor(if blockType then blockType.name else nil, if shape then shape.name else nil)
	BlockLabel.attach(model, root, title, if blockType then blockType.description else nil)
end

-- The Highlight that marks a special block. Named because Mystery re-tints it
-- in place when it reveals what it turned out to be.
local TYPE_TELL_NAME = "TypeTell"

local function buildPiece(
	shape: Shapes.Shape,
	skin: BlockSkins.Skin,
	blockType: BlockTypes.BlockType?,
	pack: SkinPacks.SkinPack?
): (Model, BasePart, Color3)
	local model = Instance.new("Model")
	model.Name = `Piece_{shape.name}`
	-- The skin keeps its material and its sounds; only the colour is rolled. A
	-- colour pack rolls within its own family instead of across the whole wheel
	-- — still a fresh shade per block, so the pieces stay legible as separate
	-- blocks rather than merging into one flat mass.
	local color = SkinPacks.colorFor(pack) or randomColor()

	local root: BasePart? = nil
	for index, cell in shape.cells do
		local part = Instance.new("Part")
		part.Name = `Cell{index}`
		part.Size = Vector3.new(Constants.BLOCK_SIZE, Constants.BLOCK_SIZE, Constants.BLOCK_DEPTH)
		part.Color = color
		-- A colour pack sets no material, so the rolled skin's own surface (and
		-- its sounds) survive underneath the tint.
		part.Material = if pack and pack.material then pack.material else skin.material
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
		highlight.Name = TYPE_TELL_NAME
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

-- The top of everything a piece could come down on: every block that is actually
-- resting, every checkpoint platform, and the base.
--
-- Deliberately wider than `state.height`, which is the *scoring* number and only
-- counts blocks that have held still for SETTLE_CONFIRM_SECONDS — and skips Noobs
-- entirely, because a walking block would make the readout bob. A block that
-- landed a quarter of a second ago and a Noob standing on the parapet are both
-- very much in the way, and spawning a piece into either is exactly how a
-- placement ends up inside the tower.
--
-- Blocks still tumbling are left out. A piece thrown up by a bomb is somewhere
-- else a moment later, and taking it for the tower's top would fire the next
-- spawn into orbit. `slowSince` is the test: it's set the instant an assembly
-- goes quiet, so it reads "resting" a good half second before `settled` does.
local function restingTopY(): number
	local top = baseTopY
	for _, block in blocks do
		if block.root.Parent == nil then
			continue
		end
		if not (block.custom or block.settled or block.slowSince ~= nil) then
			continue
		end
		for _, part in modelParts(block.model) do
			top = math.max(top, partTopY(part))
		end
	end
	for _, platform in platforms do
		top = math.max(top, partTopY(platform))
	end
	return top
end

-- How far below its pivot a piece can reach at *any* of its four quarter turns.
-- Rotating about Z swaps the piece's width and height, so the worst case is the
-- larger half extent — clearing only the current one would drop a flat I-piece
-- straight into the tower the instant the holder spun it upright.
local function pieceHalfHeight(model: Model): number
	local _, size = model:GetBoundingBox()
	return math.max(size.X, size.Y) / 2
end

-- Pivot altitude that leaves SPAWN_CLEARANCE of clear air under the piece.
local function clearPivotY(halfHeight: number): number
	return restingTopY() + halfHeight + Constants.SPAWN_CLEARANCE
end

-- Where a fresh piece appears: clear of whatever has been built so far.
local function spawnPivot(halfHeight: number): CFrame
	return CFrame.new(0, clearPivotY(halfHeight), Constants.PLANE_Z)
end

-- Put the held piece back at its clearance, so "the piece is above the tower"
-- holds for the whole turn rather than only for the instant it spawned. The tower
-- moves under the holder all the time: a Noob walks up onto the parapet, a Clone
-- drops its copy in, a block knocked loose comes to rest higher than it started.
--
-- `down` allows the piece to come back down as well as go up. Normally it may
-- only rise — a piece sinking mid-turn reads as a glitch, and it would drop the
-- holder into a gap that has since been filled — but when the storm has just
-- taken the entire tower there is nothing left to be clear of, and a piece left
-- hanging over an empty arena is worse.
--
-- Returns whether it moved, so the caller knows the state is worth broadcasting.
-- Only Y is touched; X and the holder's quarter turns are theirs.
local function reseatHeldPiece(down: boolean): boolean
	local piece = held
	if piece == nil then
		return false
	end

	local wanted = clearPivotY(piece.halfHeight)
	local shift = wanted - piece.pivot.Position.Y
	if math.abs(shift) < Constants.HEIGHT_EPSILON then
		return false
	end
	if shift < 0 and not down then
		return false
	end

	piece.pivot = piece.pivot + Vector3.new(0, shift, 0)
	piece.model:PivotTo(piece.pivot)
	state.pieceTop = wanted + piece.halfHeight - baseTopY
	return true
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
-- a 1962 brick from any angle instead of only from above.
--
-- Leaving a zone undresses the block again, because a zone is a property of the
-- world rather than of whichever zone a block happened to spawn in.
--
-- This is the *server's* say on how a block looks, and it's the same for the
-- whole room — including the placer's skin pack, which rides on the block and so
-- shows the same way on every screen. The pack outranks the zone: "a Retro zone
-- can't dull it" is the thing being sold.
-- What a block would feel like with no zone in play. Most types don't care; the
-- four that do each own one line of this table and nothing else in the file —
-- adding another is an entry here, not a branch somewhere.
local TYPE_PHYSICS: { [string]: PhysicalProperties } = {
	bouncy = Constants.BOUNCY_PHYSICS,
	anvil = Constants.ANVIL_PHYSICS,
	ice = Constants.ICE_PHYSICS,
	feather = Constants.FEATHER_PHYSICS,
}

local function basePhysics(blockType: BlockTypes.BlockType?): PhysicalProperties
	if blockType == nil then
		return Constants.BLOCK_PHYSICS
	end
	return TYPE_PHYSICS[blockType.kind] or Constants.BLOCK_PHYSICS
end

local function applyZoneLook(
	model: Model,
	skin: BlockSkins.Skin,
	blockType: BlockTypes.BlockType?,
	pack: SkinPacks.SkinPack?
)
	-- A Noob isn't scenery. Studding one over, or handing it snow friction, turns
	-- a character back into a prop.
	if model:GetAttribute(Constants.RAW_MODEL_ATTRIBUTE) then
		return
	end

	local zone = Zones.get(state.zoneId)
	-- A pack that owns the surface keeps it through every zone, so Retro only gets
	-- to stud the blocks whose placer wasn't wearing one. A colour pack doesn't
	-- own the surface, so its blocks still stud over — it owns the hue, and the
	-- two overrides don't have to fight.
	local retro = zone.kind == "retro" and not SkinPacks.ownsSurface(pack)

	-- Snow wins over everything the *surface* controls: a slippery zone is the
	-- whole point of it, so friction and elasticity are snow's whichever type the
	-- block is. Density isn't a surface, though — it's how much block there is —
	-- so it survives the zone. Without that carve-out an Anvil stops being heavy
	-- the moment it starts snowing, which reads as the type having broken rather
	-- than as the weather. Bouncy is unaffected either way; its density is the
	-- ordinary one.
	local base = basePhysics(blockType)
	local snow = Constants.SNOWY_PHYSICS
	local physics = if zone.kind == "snowy"
		then PhysicalProperties.new(
			base.Density,
			snow.Friction,
			snow.Elasticity,
			snow.FrictionWeight,
			snow.ElasticityWeight
		)
		else base

	for _, part in modelParts(model) do
		if retro then
			part.Material = Enum.Material.Plastic
			setSurfaces(part, Enum.SurfaceType.Studs)
		else
			part.Material = if pack and pack.material then pack.material else skin.material
			setSurfaces(part, Enum.SurfaceType.Smooth)
		end
		part.CustomPhysicalProperties = physics
	end
end

-- Re-dress everything already standing when the zone changes, so a zone is a
-- property of the world rather than of whatever happened to spawn during it.
local function applyZoneToTower()
	-- Gravity is the one zone rule that isn't per-block: Space drops it to a
	-- sixth, everything else puts it back. Server-owned, so it replicates.
	workspace.Gravity = Zones.gravityOf(state.zoneId)

	for _, block in blocks do
		applyZoneLook(block.model, block.skin, block.blockType, block.pack)
	end
	local piece = held
	if piece then
		applyZoneLook(piece.model, piece.skin, piece.blockType, piece.pack)
	end
end

-- Force the tower straight into a given zone, outside the usual "roll one on
-- checkpoint clear" path. Used by the "zone" cmdr command — everything a real
-- zone change does (re-dress the tower, re-roll the sky, flip gravity), just
-- triggered on demand rather than by clearing a stage.
function TowerService.setZone(zoneId: number)
	state.zoneId = zoneId
	state.zoneSky = math.random(1, 255)
	applyZoneToTower()
	broadcast()
end

-- (The Stormy zone's lightning lives further down, next to the explosion code it
-- reuses — see `strikeLightning`.)

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

	-- This runs at AIM_INTERVAL (30Hz) for whoever is holding, so both steps are
	-- gated on the piece having actually moved rather than on a packet having
	-- arrived — the client streams a position whether or not the player touched
	-- anything, and a "Steered" fired on arrival would report every turn as
	-- steered and measure nothing.
	--
	-- Pieces spawn centred and unrotated (see spawnPivot), so displacement from
	-- zero is the test. A stud of slop keeps a resting thumb on a gamepad stick
	-- from counting as intent.
	if math.abs(clampedX) > 1 then
		AnalyticsService.step(player, "turn", "Steered")
	end
	if quarter ~= 0 then
		AnalyticsService.step(player, "turn", "Rotated")
	end
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

	-- Once for the block, not once per weld: a piece settling against four
	-- neighbours would otherwise fire this four times on the same frame.
	Sfx.playAt("Glue", block.root)
end

-- Every explosion in the game goes through here — the Bomb type, the Stormy
-- zone's lightning and the Nuke product all — so a strike behaves the way
-- players have already learned bombs behave, and there is one blast to tune
-- rather than three.
--
-- `targets` is which blocks the impulse looks at, defaulting to the live tower.
-- The nuke passes its own list because it takes the tower out of `blocks`
-- before it starts detonating: the wreck is no longer the tower, but it's still
-- exactly what the blasts are supposed to be throwing.
local function blastAt(
	origin: Vector3,
	radius: number,
	pressure: number,
	impulse: number,
	exclude: Block?,
	targets: { Block }?
)
	local explosion = Instance.new("Explosion")
	explosion.Position = origin
	explosion.BlastRadius = radius
	explosion.BlastPressure = pressure
	-- Our pieces are held together by WeldConstraints, which an Explosion doesn't
	-- break — so this throws blocks around without dissolving them into cells.
	explosion.DestroyJointRadiusPercent = 0
	explosion.Parent = workspace

	-- BlastPressure alone barely shifts a welded assembly, so throw everything in
	-- radius by hand. Falls off with distance, so the blast has a shape rather
	-- than flinging the whole tower equally.
	for _, other in targets or blocks do
		local root = other.root
		if root.Parent == nil or other == exclude then
			continue
		end
		local offset = root.Position - origin
		local distance = offset.Magnitude
		if distance > radius then
			continue
		end
		local falloff = 1 - distance / radius
		-- Bias upward so the tower erupts rather than being swept sideways.
		local direction = (offset.Unit + Vector3.new(0, 0.6, 0)).Unit
		root:ApplyImpulse(direction * impulse * falloff * root.AssemblyMass)
	end
end

local function detonateBlock(block: Block)
	local origin = block.root.Position
	blastAt(origin, Constants.EXPLOSION_RADIUS, Constants.EXPLOSION_PRESSURE, Constants.EXPLOSION_IMPULSE, block)
	-- On a throwaway marker rather than the block: the block is about to be
	-- destroyed, and a sound parented to it would go with it.
	Sfx.playAtPosition("Explosion", origin, Constants.EXPLOSION_VOLUME)
	block.model:Destroy()
end

-- Lightning: the Stormy zone's hazard, and a *punctuated* one rather than the
-- constant lean the wind used to be.
--
-- Wind was a poor hazard for this game. It applied every frame to every block,
-- so there was no moment to react to — the tower slowly argued with itself and
-- nothing a player did changed that. A strike is the opposite: it lands
-- somewhere specific, you see it happen, and the damage is local.
-- Where the next bolt will land, chosen a full LIGHTNING_WARNING_SECONDS before
-- it does. A random spot on the play plane rather than a chosen block: the storm
-- isn't aiming at anyone, and picking a *place* is what lets the warning appear
-- before there's anything standing there to hit.
local function chooseStrike()
	local arena = workspace:FindFirstChild(Constants.ARENA_NAME)
	if arena == nil then
		return
	end

	-- Only the X is chosen. The bolt lands on whatever is highest in that column
	-- at the moment it strikes, which is resolved *then* rather than now — ten
	-- seconds is long enough for the players to have built something new under
	-- the warning, and the strike should hit what's actually there.
	pendingStrikeX = (math.random() * 2 - 1) * Constants.STEER_LIMIT_X
	strikeDueAt = os.clock() + Constants.LIGHTNING_WARNING_SECONDS
	-- Only the X goes out. The marker is a full column and the client stands it
	-- on the floor the run is currently building from — an altitude that moves
	-- every checkpoint, and one the client already tracks for its camera. Sending
	-- the arena's base instead left the column hundreds of studs *below* the play
	-- area a few stages in, which is a warning nobody can see.
	arena:SetAttribute(Constants.WARN_ATTRIBUTE, pendingStrikeX)
end

-- The top of whatever stands in `x`'s column, or the base if nothing does. This
-- is what the bolt actually hits — resolved at strike time, not when the warning
-- went up, so ten seconds of building under the marker counts.
local function highestAt(x: number): Vector3
	local best = baseTopY
	for _, block in blocks do
		if block.root.Parent == nil then
			continue
		end
		for _, part in modelParts(block.model) do
			-- Half a cell either side: a column as wide as the piece it's aimed
			-- at, so a bolt can't slip between two neighbouring blocks.
			if math.abs(part.Position.X - x) > Constants.BLOCK_SIZE / 2 then
				continue
			end
			local top = partTopY(part)
			if top > best then
				best = top
			end
		end
	end
	for _, platform in platforms do
		if math.abs(platform.Position.X - x) <= platform.Size.X / 2 then
			best = math.max(best, partTopY(platform))
		end
	end
	return Vector3.new(x, best, Constants.PLANE_Z)
end

local function strikeLightning(origin: Vector3)
	local arena = workspace:FindFirstChild(Constants.ARENA_NAME)
	if arena then
		-- Warning off first, bolt second. A client that saw both attributes change
		-- in the same frame should be left with a flash and no marker, never the
		-- other way round.
		arena:SetAttribute(Constants.WARN_ATTRIBUTE, nil)
		-- Every client draws the bolt off this attribute. The server says only
		-- *where* it struck; attributes replicate, so the flash costs no packet
		-- of its own and a client that misses it simply doesn't draw one.
		arena:SetAttribute(Constants.STRIKE_ATTRIBUTE, origin)
	end

	Sfx.playAtPosition("Lightning", origin, Constants.LIGHTNING_VOLUME)
	blastAt(origin, Constants.LIGHTNING_RADIUS, Constants.LIGHTNING_PRESSURE, Constants.LIGHTNING_IMPULSE)
end

-- Drives the strikes while a Stormy zone is up: choose a spot, warn for ten
-- seconds, land the bolt, wait a randomised gap, repeat.
--
-- The gap is measured from the last strike and the warning sits *inside* it, so
-- raising the warning doesn't quietly slow the storm down.
local function updateLightning()
	-- Normally the Stormy zone's hazard; the Lightning Storm gamemode turns it
	-- on everywhere for the whole round.
	if Zones.get(state.zoneId).kind ~= "stormy" and not stage.alwaysLightning then
		-- Leaving the zone mid-warning must take the marker with it, or a red
		-- column is left standing over a zone that has no lightning in it.
		if pendingStrikeX ~= nil then
			pendingStrikeX = nil
			local arena = workspace:FindFirstChild(Constants.ARENA_NAME)
			if arena then
				arena:SetAttribute(Constants.WARN_ATTRIBUTE, nil)
			end
		end
		return
	end

	local now = os.clock()
	local pendingX = pendingStrikeX
	if pendingX ~= nil then
		if now < strikeDueAt then
			return
		end
		pendingStrikeX = nil
		nextStrikeAt = now
			+ Constants.LIGHTNING_MIN_SECONDS
			+ math.random() * (Constants.LIGHTNING_MAX_SECONDS - Constants.LIGHTNING_MIN_SECONDS)
		strikeLightning(highestAt(pendingX))
		return
	end

	-- Nothing pending: start the next warning once the gap has run down, minus
	-- the warning it has to fit in.
	if now >= nextStrikeAt - Constants.LIGHTNING_WARNING_SECONDS then
		chooseStrike()
	end
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
	custom: boolean,
	pack: SkinPacks.SkinPack?
): Block
	local block: Block = {
		model = model,
		root = root,
		settled = false,
		slowSince = nil,
		settledOnce = false,
		shape = shape,
		skin = skin,
		pack = pack,
		blockType = blockType,
		baseColor = baseColor,
		custom = custom,
		impactSound = attachSound(root, "Impact", skin.impactSound, skin.volume),
		settleSound = if skin.settleSound
			then attachSound(root, "Settle", skin.settleSound, skin.volume * 0.6)
			else nil,
		speed = 0,
		resolved = false,
		shattered = false,
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

	-- The copy inherits the original's pack, so a neon block clones into a neon
	-- one rather than quietly reverting to the stock look mid-tower.
	local model, root, color = buildPiece(shape, block.skin, nil, block.pack)
	applyZoneLook(model, block.skin, nil, block.pack)

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
	registerBlock(model, root, shape, block.skin, nil, color, false, block.pack)
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

	-- Solid before it's loose, so the first frame of physics already has the piece
	-- colliding with the tower rather than a frame of it falling through.
	restoreCollision(piece.model, piece.collision)
	for _, part in modelParts(piece.model) do
		part.Anchored = false
	end

	registerBlock(
		piece.model,
		piece.root,
		piece.shape,
		piece.skin,
		piece.blockType,
		piece.baseColor,
		piece.custom,
		piece.pack
	)
	-- Everyone hears the drop from where it happened. The holder also gets their
	-- own confirmation cue locally (Drop2, played client-side).
	Sfx.playAt("Drop", piece.root)
	lastDropper = piece.player
	placerOf[piece.model] = piece.player
	TowerStatsService.recordBlockPlaced(piece.player)

	AnalyticsService.step(piece.player, "turn", "Dropped")
	-- Only the first placement of the round advances the round funnel; `step`
	-- dedupes the rest against the session, so this is called on every drop and
	-- counted once.
	AnalyticsService.step(piece.player, "round", "First Piece Placed")
	AnalyticsService.onboarding(piece.player, 3)

	state.phase = PHASE.SETTLING
	state.holderUserId = 0
	state.turnEndsAt = 0
	state.shapeId = 0
	state.blockTypeId = 0
	state.pieceTop = 0
	broadcast()
end

local function beginTurn(player: Player)
	local shape: Shapes.Shape? = nextShape
	nextShape = Shapes.random()

	-- Rolled per piece. Skin is pure flavour; type is the hazard, and it gets
	-- likelier the more floors the run has cleared. Either can be pinned for
	-- exactly this one piece by the "block" cmdr command.
	local commanded = skinForced
	local skin = if commanded then forcedSkin :: BlockSkins.Skin else BlockSkins.random()
	local blockType = if blockTypeForced
		then forcedBlockType
		else BlockTypes.roll(state.checkpoints, stage.blockTypeScale, stage.blockTypeChance)
	skinForced = false
	blockTypeForced = false

	-- Read once, here, and carried on the piece for the rest of its life. Taking
	-- it per-frame would let a block change look under the room when its placer
	-- swapped packs after dropping it.
	local pack = SkinPacks.get(StoreService.equipped(player, SkinPacks.KIND))

	-- A pack that pins a skin (Needoh) replaces the roll rather than tinting it:
	-- the surface, the transparency and both sounds come from that one skin, so
	-- every block its owner drops squishes. The "block" command still wins —
	-- it's a debug pin and has to be able to show any skin on demand.
	if not commanded then
		skin = SkinPacks.blockSkinFor(pack) or skin
	end

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
		model, root, color = buildPiece(shape, skin, blockType, pack)
	else
		-- No silhouette to name, so the plate is just the type.
		shape = nil
		labelPiece(model :: Model, root :: BasePart, nil, blockType)
	end

	local piece = model :: Model
	applyZoneLook(piece, skin, blockType, pack)
	local halfHeight = pieceHalfHeight(piece)
	local pivot = spawnPivot(halfHeight)
	piece:PivotTo(pivot)
	-- Nothing the holder is still aiming may touch the tower.
	local collision = suspendCollision(piece)
	-- Tells the holder's client "this one is yours" so it can hide the real piece
	-- and drive a local preview instead.
	piece:SetAttribute(Constants.HELD_ATTRIBUTE, player.UserId)
	piece.Parent = arena

	held = {
		model = piece,
		root = root :: BasePart,
		shape = shape,
		skin = skin,
		pack = pack,
		blockType = blockType,
		baseColor = color :: Color3,
		custom = shape == nil,
		pivot = pivot,
		halfHeight = halfHeight,
		collision = collision,
		player = player,
	}

	state.phase = PHASE.AIMING
	state.pieceTop = pivot.Position.Y + halfHeight - baseTopY
	state.holderUserId = player.UserId
	state.turnEndsAt = workspace:GetServerTimeNow() + stage.turnSeconds
	-- 0 for a piece with no silhouette; the HUD names it from blockTypeId instead.
	state.shapeId = if shape then shape.id else 0
	state.blockTypeId = if blockType then blockType.id else 0
	state.nextShapeId = nextShape.id
	broadcast()

	-- A fresh turn funnel session per piece, tagged with what they were handed:
	-- the drop-off between "Piece Received" and "Dropped" is a timeout, and
	-- knowing which block type was sitting there when it happened is the
	-- difference between "turns are too short" and "nobody knows what a Crate
	-- does". Both fields are low-cardinality, which is what custom fields want.
	AnalyticsService.start(player, "turn", "Piece Received", {
		if blockType then blockType.name else "Plain",
		if pack then pack.id else "None",
	})
	AnalyticsService.onboarding(player, 2)
end

-- ---------------------------------------------------------------- the plane --

-- Hold one loose part of a broken-open Crate to the play plane.
--
-- The ordinary clamp steers a whole piece by its root, which works because the
-- cells are welded into one assembly and share the root's drift. Cut the welds
-- and that stops being true: each cell is its own assembly and wanders on its
-- own. This is the same Z correction, just applied per part — and only to the
-- handful of blocks that have actually been broken open.
--
-- No straightening: a pile of loose cubes is *supposed* to sit at angles. The
-- flat silhouette the tilt clamp protects is a property of a piece, and a broken
-- crate isn't a piece any more.
local function clampLooseCell(part: BasePart)
	local velocity = part.AssemblyLinearVelocity
	if velocity.Z ~= 0 then
		part.AssemblyLinearVelocity = Vector3.new(velocity.X, velocity.Y, 0)
	end

	local drift = part.Position.Z - Constants.PLANE_Z
	if math.abs(drift) > Constants.PLANE_TOLERANCE then
		part.CFrame = part.CFrame - Vector3.new(0, 0, drift)
	end
end

local function clampToPlane(deltaTime: number)
	for _, block in blocks do
		local root = block.root
		if root.Parent == nil then
			continue
		end

		-- A broken crate has no single assembly to steer, so every cell is held
		-- to the plane on its own and the piece-shaped clamp below is skipped.
		if block.shattered then
			for _, part in modelParts(block.model) do
				clampLooseCell(part)
			end
			continue
		end

		local velocity = root.AssemblyLinearVelocity
		local spin = root.AssemblyAngularVelocity

		-- Sampled before the collision damps it: Touched fires *after* physics has
		-- resolved the hit, so reading velocity there would report a block that has
		-- already stopped. This is the speed the impact sound is scaled by.
		block.speed = velocity.Magnitude

		local resting = velocity.Magnitude < Constants.PLANE_RESTING_SPEED
			and spin.Magnitude < Constants.PLANE_RESTING_SPEED

		-- Velocity only needs clamping while there *is* velocity, and writing it
		-- to a sleeping assembly would wake it every frame for nothing.
		if not resting then
			-- A Feather has a terminal velocity: it never falls faster than a
			-- drift, however far it has to come down. Only the downward half is
			-- capped, so it can still be thrown by a blast — and only while it's
			-- falling, so a settled one is never written to.
			--
			-- Folded into the Z clamp's write rather than done separately: one
			-- AssemblyLinearVelocity assignment per block per frame, same as before.
			local fall = velocity.Y
			if
				block.blockType ~= nil
				and block.blockType.kind == "feather"
				and fall < -Constants.FEATHER_FALL_SPEED
			then
				fall = -Constants.FEATHER_FALL_SPEED
			end
			if velocity.Z ~= 0 or fall ~= velocity.Y then
				root.AssemblyLinearVelocity = Vector3.new(velocity.X, fall, 0)
			end
			-- Only in-plane spin (about Z) survives; tipping toward or away from
			-- the camera is what we're suppressing. Custom models are exempt: a
			-- Noob turns about Y to face the way it's walking, and zeroing that
			-- would leave it moonwalking on the spot. It's still pinned to the
			-- plane by the Z terms.
			if not block.custom and (spin.X ~= 0 or spin.Y ~= 0) then
				root.AssemblyAngularVelocity = Vector3.new(0, 0, spin.Z)
			end
		end

		-- Position and orientation are corrected whether or not the block is
		-- resting — a block that came to rest skewed is exactly the case that
		-- needs fixing, and it will never be moving again to be caught otherwise.
		-- Both are guarded by a tolerance, so a block that's already flat is
		-- never written to and never woken.
		local cf = root.CFrame

		-- Every cell of a piece shares one Z (pieces only ever rotate about Z), so
		-- the root's drift is the assembly's drift. Nudging the root drags the
		-- welded assembly with it; Model:PivotTo is no use here because a model's
		-- WorldPivot doesn't track parts the physics engine moved.
		local drift = cf.Position.Z - Constants.PLANE_Z
		if math.abs(drift) > Constants.PLANE_TOLERANCE then
			cf = cf - Vector3.new(0, 0, drift)
			root.CFrame = cf
		end

		-- Straighten. A Noob is exempt from the angular half of the clamp, so it's
		-- exempt here too — it has to be allowed to turn around.
		if block.custom then
			continue
		end

		-- LookVector is the part's -Z axis. In-plane it points straight at (or
		-- away from) the camera, so how far |Z| falls short of 1 is exactly how
		-- far the block has tipped, with no angle extraction needed.
		local tilt = 1 - math.abs(cf.LookVector.Z)
		if tilt <= Constants.PLANE_TILT_TOLERANCE then
			continue
		end

		-- The rotation worth keeping. For a pure Z rotation RightVector is
		-- (cos, sin, 0), so its angle in the XY plane is the block's in-plane
		-- spin — rebuilt around that and nothing else.
		local right = cf.RightVector
		local flat = CFrame.new(cf.Position) * CFrame.Angles(0, 0, math.atan2(right.Y, right.X))

		if resting then
			-- Settled and skewed: snap. One write, and next frame it's inside
			-- tolerance, so this doesn't repeat.
			root.CFrame = flat
		else
			-- Mid-flight: ease, or a tumbling piece would visibly teleport
			-- upright. Framerate-independent, like every other follow here.
			root.CFrame = cf:Lerp(flat, 1 - math.exp(-Constants.PLANE_STRAIGHTEN_RATE * deltaTime))
		end
	end
end

-- ---------------------------------------------------------------- the storm --
--
-- The pressure mechanic. Every stage names a height to beat before the clock
-- runs out; clearing it welds a permanent floor onto the tower at whatever
-- altitude the players got to, and sets a higher bar.

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
-- Nothing survives a demolition, including an Anchor block — it holds itself up
-- against the tower, not against the storm. An assembly is only loose once every
-- part of it is, so this is all of them rather than the root.
local function unanchorModel(model: Model)
	for _, part in modelParts(model) do
		if part.Anchored then
			part.Anchored = false
		end
	end
end

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
		unanchorModel(block.model)
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

-- The floors under the new one, thrown clear the same way the scaffolding is.
--
-- A checkpoint platform is the ground only until the next one lands above it.
-- After that it's a slab hanging in dead air with nothing standing on it and
-- nothing able to reach it — and the overview shot would frame the whole dead
-- stack instead of the tower the players are actually building.
--
-- Taken out of `platforms` *before* they're shoved, for the same reason
-- `blastBlocksBelow` empties its list first: that list feeds `restingTopY`, and
-- a slab thrown upward by the blast would otherwise read as the top of the tower
-- and fire the next piece's spawn into orbit.
--
-- The base is not a platform and is never in this list. It stays: it's where the
-- run restarts after the storm, and in a Studio-built place it's the user's own
-- tagged part rather than something this file made.
local function blastPlatformsBelow(cutoffY: number): { BasePart }
	local debris = {}
	for index = #platforms, 1, -1 do
		local platform = platforms[index]
		if partTopY(platform) > cutoffY then
			continue
		end
		table.remove(platforms, index)
		table.insert(debris, platform)

		platform.Anchored = false
		-- Straight through the new floor and anything else on the way down. These
		-- are deleted in a moment, and a tumbling slab that still collides would
		-- shove a block that survived the cutoff or swallow the landing preview's
		-- raycast on its way past.
		platform.CanCollide = false
		platform.CanQuery = false
		platform.CanTouch = false
		platform.AssemblyLinearVelocity = Vector3.new(
			(math.random() * 2 - 1) * Constants.CHECKPOINT_BLAST_HORIZONTAL,
			Constants.CHECKPOINT_BLAST_UP * (0.5 + math.random()),
			(math.random() * 2 - 1) * Constants.CHECKPOINT_BLAST_HORIZONTAL * 0.5
		)
		platform.AssemblyAngularVelocity = Vector3.new(
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
	-- Numbered by the floor it is, not by how many are currently standing —
	-- previous ones are demolished, so `#platforms` would name every floor after
	-- the first "Checkpoint2". `state.checkpoints` is still the count *behind*
	-- this one at spawn time; it's incremented once the demolition finishes.
	part.Name = `Checkpoint{state.checkpoints + 1}`
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
		unanchorModel(block.model)
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
	-- The tower the held piece was parked above no longer exists, so bring it
	-- back down to the base instead of leaving it (and the camera following it)
	-- hanging over an empty arena for the rest of the turn.
	reseatHeldPiece(true)

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
	-- A run starts un-voted; last run's gamemode doesn't carry over. The round
	-- break overwrites this with whatever the players then vote for — this is the
	-- baseline for the paths that reset without a vote (server start).
	applyStage(Gamemodes.DEFAULT)
	state.stormEndsAt = workspace:GetServerTimeNow() + stage.stormSeconds
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
-- True from the moment the storm takes the tower until the next round starts:
-- the wreck, the white fade, and the gamemode vote all live inside it. Declared
-- here beside `checkpointActive` because the two gate the same things, and every
-- one of those gates has to name both. See `runRoundBreak`.
local intermission = false

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
	state.pieceTop = 0
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
		-- The floors the run has already climbed past go with it. The new platform
		-- was pushed onto `platforms` a moment ago and its top sits above the
		-- cutoff, so it isn't caught by its own demolition.
		local oldFloors = blastPlatformsBelow(cutoff)
		Sfx.playAtPosition("Explosion", Vector3.new(0, cutoff, Constants.PLANE_Z), Constants.EXPLOSION_VOLUME)

		task.wait(Constants.CHECKPOINT_BLAST_SECONDS)
		for _, block in debris do
			block.model:Destroy()
		end
		for _, floor in oldFloors do
			floor:Destroy()
		end

		-- Only now does the stage actually advance.
		state.checkpoints += 1

		-- Clearing a checkpoint is what moves the run into a new zone. The count
		-- has just been incremented, so this asks for the zone *after* the ones
		-- already cleared — which is what puts the specials on the cadence.
		local zone = Zones.next(state.checkpoints, state.zoneId)
		state.zoneId = zone.id
		state.zoneSky = math.random(1, 255)
		applyZoneToTower()
		CashService.awardZone()
		reportStageCleared(state.checkpoints)

		-- Note what does *not* happen here: the gamemode is not re-voted. The vote
		-- belongs to the round break (`runRoundBreak`), so the modifier the players
		-- picked holds for every stage of the round — clearing a checkpoint
		-- shouldn't change the rules out from under a run in progress.

		-- Each floor is a little further out than the last.
		stormGap += Constants.STORM_GAP_GROWTH
		-- The next bar is measured from what they actually reached, not from the
		-- target they just cleared, so overshooting doesn't make the next stage
		-- trivial. That reached height is also where the progress line now
		-- starts from.
		state.zoneBaseHeight = height
		state.targetHeight = height + stormGap
		state.stormEndsAt = workspace:GetServerTimeNow() + stage.stormSeconds
		state.phase = PHASE.SETTLING
		broadcast()

		-- The camera is on its way back in; let it land before a piece appears.
		task.wait(Constants.CHECKPOINT_RESUME_SECONDS)
		checkpointActive = false
	end)
end

-- Clear the current stage by jumping straight to the target height — the
-- altitude the players haven't actually built to yet. The full checkpoint
-- sequence still runs (cutscene, platform, blast, zone roll), so this is the
-- same event a stage clear would have been, just reached without playing it
-- out. That's the point for a paying "Skip"/"Next Checkpoint" purchase: it
-- buys the players the climb, not merely a floor wherever they happened to
-- stop. Returns false if a checkpoint is already running.
function TowerService.clearStage(): boolean
	if checkpointActive or intermission then
		return false
	end
	runCheckpoint(state.targetHeight)
	return true
end

-- Push the storm back by `seconds`, giving the room more of the current stage.
--
-- Added to `stormEndsAt` rather than recomputed from now, which is what makes
-- the purchase stack honestly: buying twice buys two minutes, and buying early
-- is worth exactly as much as buying late. Recomputing from now would quietly
-- punish the second purchase and reward panic-buying at zero.
--
-- Refused during a checkpoint or a round break, like the other two products.
-- Both sequences set `stormEndsAt` themselves when they end, so time added
-- inside one is time thrown away — and Store leaves the receipt undelivered on
-- a false, so the player gets their minute a moment later instead of losing it.
function TowerService.extendStorm(seconds: number): boolean
	if checkpointActive or intermission then
		return false
	end
	if seconds <= 0 then
		return false
	end

	state.stormEndsAt += seconds
	broadcast()
	return true
end

-- Pin the very next piece's type and/or skin, overriding the usual roll. Used
-- by the "block" cmdr command. `blockType = nil` forces a plain piece (the
-- command's "normal" default); `skin = nil` leaves the skin to roll normally.
-- One-shot: `beginTurn` consumes and clears both flags the moment it reads them.
function TowerService.forceNextBlock(blockType: BlockTypes.BlockType?, skin: BlockSkins.Skin?)
	blockTypeForced = true
	forcedBlockType = blockType
	skinForced = skin ~= nil
	forcedSkin = skin
end

-- ---------------------------------------------------------- the round break --
--
-- The storm taking the tower ends the round. What follows is the one moment the
-- whole game is stopped: the wreck flies, clients fade the screen white off
-- PHASE.GAMEOVER, the players vote on how the next round plays, and only then
-- does a fresh run start on the numbers they picked.
--
-- `intermission` is what makes "paused" true rather than cosmetic. It parks the
-- turn queue, freezes the storm clock, stops the height poll from measuring
-- debris, and refuses every placement intent — so the vote isn't a screen over a
-- game still running underneath it.
--
-- The modifier is applied *here* and nowhere else, which is what makes a voted
-- mode last a whole round: `runCheckpoint` deliberately doesn't touch it.

local function runRoundBreak()
	if intermission then
		return
	end
	intermission = true

	-- The holder loses the piece rather than being left aiming at a tower that's
	-- being blown apart under them.
	cancelHeldPiece()
	-- Before resetRun, which zeroes the checkpoint count this reports on.
	reportRoundLost(state.checkpoints)
	resetRun()
	state.phase = PHASE.GAMEOVER
	broadcast()

	task.spawn(function()
		-- Let the wreck read as a consequence before a UI opens over it.
		task.wait(Constants.ROUND_BREAK_WRECK_SECONDS)

		-- Yields for the length of the poll. An unregistered or skipped vote comes
		-- back nil, and `modifierFor` turns that into the Classic numbers — the
		-- same round winning the Classic panel would have produced.
		applyStage(Gamemodes.modifierFor(GamemodeVoteService.startVote()))

		-- The new round's clock starts once the rules are known, so the players
		-- don't lose any of it to the vote they were made to sit through.
		state.stormEndsAt = workspace:GetServerTimeNow() + stage.stormSeconds
		state.phase = PHASE.SETTLING
		broadcast()

		-- Here rather than in `resetRun`: the round the players are in starts
		-- when the rules are known and the clock is running, not when the last
		-- one's wreckage was cleared. Counting from resetRun would put the whole
		-- vote inside the round funnel's first step.
		reportRoundStarted()

		task.wait(Constants.ROUND_BREAK_RESUME_SECONDS)
		intermission = false
	end)
end

-- Everything standing, cut loose in one go: out of the live list and unanchored,
-- so it stops being architecture and starts being physics. Returns the wreck,
-- because the barrage still has to throw it and the cleanup still has to sweep
-- it after `blocks` has stopped naming it.
--
-- Taking it out of `blocks` up front is what the storm and a checkpoint
-- demolition both do, and for the same two reasons: the plane clamp only holds
-- live blocks, so the wreck is free to scatter in 3D instead of sliding along
-- the play plane; and the height poll stops measuring it, so a settled block
-- flung skyward can't be read as a taller tower and clear the stage out of its
-- own debris.
local function tearTowerLoose(): { Block }
	local debris = blocks
	blocks = {}
	table.clear(blockByModel)

	for _, block in debris do
		if block.root.Parent == nil then
			continue
		end
		unanchorModel(block.model)
	end

	return debris
end

-- Blow the tower apart on demand — and *only* the tower. The run itself carries
-- on: the checkpoints stand, the storm clock keeps counting, the zone and the
-- voted gamemode are untouched, and the queue never stops. What the players lose
-- is everything they'd stacked above the last floor, which is what a nuke is
-- supposed to cost them.
--
-- Deliberately not the round break. That's the storm's outcome — wreck, white
-- fade, vote, fresh run — and routing a purchase through it made a nuke worth
-- less than it sounds: it handed the room a clean slate and a new gamemode a
-- moment later, so the tower it destroyed was one nobody had to rebuild.
--
-- Returns false while a checkpoint or a round break is running — those sequences
-- own the world for their duration, and detonating the tower under a camera
-- holding a wide shot of it would read as a bug. The caller (a Robux purchase)
-- treats false as "not now" and leaves the receipt for redelivery.
function TowerService.nuke(): boolean
	if checkpointActive or intermission then
		return false
	end

	-- Measured before the tower comes out of the list, because `state.height` is
	-- about to fall back to the last checkpoint floor and the barrage is aimed at
	-- what was standing a moment ago.
	local top = state.height
	local debris = tearTowerLoose()

	-- A nuke should look like one: blasts walked up the tower, several abreast at
	-- each rung so the whole play plane goes up rather than one column of it, and
	-- spaced in time so they read as a chain rather than a single frame in which
	-- everything vanishes.
	--
	-- Fired against the tower's own height so the barrage covers what was
	-- actually built: on a tall stack it climbs, on a short one it stays low.
	task.spawn(function()
		for rung = 1, Constants.NUKE_BLASTS do
			local fraction = rung / Constants.NUKE_BLASTS
			for column = 1, Constants.NUKE_BLASTS_ACROSS do
				-- Spread across the steering limit rather than rolled at random:
				-- a random X can put every blast of a rung in the same place, and
				-- "everywhere" is the whole point of this one. The jitter is what
				-- keeps the grid from being visible as a grid.
				local spread = (column - 0.5) / Constants.NUKE_BLASTS_ACROSS * 2 - 1
				local jitter = (math.random() * 2 - 1) * Constants.NUKE_BLAST_JITTER
				blastAt(
					Vector3.new(
						math.clamp(spread + jitter, -1, 1) * Constants.STEER_LIMIT_X,
						baseTopY + top * fraction,
						Constants.PLANE_Z
					),
					Constants.NUKE_RADIUS,
					Constants.NUKE_PRESSURE,
					Constants.NUKE_IMPULSE,
					nil,
					-- The wreck, not `blocks` — which is empty by now, and would
					-- otherwise mean a nuke that detonates over nothing.
					debris
				)
			end
			task.wait(Constants.NUKE_BLAST_INTERVAL)
		end
	end)

	Sfx.playAtPosition("Explosion", Vector3.new(0, baseTopY + top / 2, Constants.PLANE_Z), Constants.EXPLOSION_VOLUME)

	-- Outlives the barrage by design (see NUKE_WRECK_SECONDS): a piece cleaned up
	-- mid-chain would vanish out of a blast that was about to throw it.
	task.delay(
		Constants.NUKE_BLASTS * Constants.NUKE_BLAST_INTERVAL + Constants.NUKE_WRECK_SECONDS,
		function()
			for _, block in debris do
				block.model:Destroy()
			end
		end
	)

	-- The holder keeps their piece — the turn didn't end, only the tower did —
	-- but it was parked clear of a stack that no longer exists, so bring it back
	-- down rather than leaving it (and the camera following it) hanging in the
	-- air for the rest of the turn.
	reseatHeldPiece(true)
	-- Don't make the clients wait a poll to find out the tower is gone. The
	-- height is recomputed here rather than left for the poll, because a
	-- broadcast carrying the old height beside a block count of zero is a state
	-- that never existed. `restingTopY` reads the checkpoint floors now that
	-- `blocks` is empty, which is exactly what the poll is about to conclude.
	state.height = restingTopY() - baseTopY
	broadcast()
	return true
end

-- Returns true when the stage changed and clients need to hear about it.
local function updateStorm(height: number): boolean
	local now = workspace:GetServerTimeNow()

	-- Nothing here runs during a checkpoint or a round break: `updateHeight`
	-- returns before it gets this far, which is also what freezes the storm clock
	-- through the vote — `runRoundBreak` sets `stormEndsAt` fresh when the new
	-- round's rules are known, so no part of the round is spent on the poll.

	-- Nobody playing: hold the clock rather than letting it expire against an
	-- empty server.
	if #queue == 0 then
		state.stormEndsAt = now + stage.stormSeconds
		return false
	end

	if height >= state.targetHeight then
		runCheckpoint(height)
		return true
	end

	if now >= state.stormEndsAt then
		runRoundBreak()
		return true
	end

	return false
end

-- --------------------------------------------------------------- the height --

-- Anchor blocks: the moment one comes to rest it stops being physics and starts
-- being architecture. Anchored rather than welded to its neighbours, so it holds
-- *itself* and nothing else — a bomb can still clear the blocks around it, and
-- what's left is a ledge hanging in the air where the anchor was.
--
-- Every part, not just the root: the cells are welded into one assembly, and an
-- assembly is only anchored if all of it is.
local function anchorBlock(block: Block)
	block.root.AssemblyLinearVelocity = Vector3.zero
	block.root.AssemblyAngularVelocity = Vector3.zero
	for _, part in modelParts(block.model) do
		part.Anchored = true
	end
end

-- Crate blocks: the welds come out and the piece collapses into the loose cubes
-- it was pretending to be.
--
-- Breaking on *settle* rather than on impact is deliberate. A crate that came
-- apart the instant it grazed something would scatter its cells on the way down
-- and read as the piece failing to exist; landing first, then falling apart, is
-- one beat the room can watch — and it's the same "where it ends up, not where
-- it first grazed" rule Glue and Clone already follow.
--
-- The cells stay inside the one model and the one Block entry: they're still
-- the same tower mass, they still get destroyed together by the demolition, and
-- `shattered` is what tells the plane clamp to hold each of them separately now
-- that they're no longer one assembly.
local function shatterBlock(block: Block)
	local cells = modelParts(block.model)
	-- A one-cell piece has no welds and nothing to break into. Nothing to do
	-- beats a Crate that visibly does nothing.
	if #cells < 2 then
		return
	end
	block.shattered = true

	for _, descendant in block.model:GetDescendants() do
		if descendant:IsA("WeldConstraint") then
			descendant:Destroy()
		end
	end

	-- Out and up, never sideways in Z: a scatter with any depth in it would throw
	-- cells out of the play plane faster than the clamp pulls them back.
	for _, part in cells do
		part.AssemblyLinearVelocity = Vector3.new(
			(math.random() * 2 - 1) * Constants.CRATE_SCATTER,
			Constants.CRATE_LIFT * math.random(),
			0
		)
		part.AssemblyAngularVelocity = Vector3.new(0, 0, (math.random() * 2 - 1) * Constants.CRATE_SPIN)
	end

	-- The skin's own landing sound, played a second time. A crate coming apart is
	-- a percussive event and the skin already has the right noise for one, so this
	-- costs no new Studio asset.
	if block.impactSound then
		block.impactSound:Play()
	end
end

-- Run a type's landing effect. Shared by the types that resolve on settle and by
-- Mystery, which needs to be able to fire any of them after the fact.
local function applySettleEffect(block: Block, blockType: BlockTypes.BlockType)
	local kind = blockType.kind
	if kind == "glue" then
		glueBlock(block)
	elseif kind == "clone" then
		spawnCloneOf(block)
	elseif kind == "anchor" then
		anchorBlock(block)
	elseif kind == "crate" then
		shatterBlock(block)
	elseif kind == "burning" then
		igniteBlock(block)
	elseif kind == "explosion" then
		-- Only reachable through a Mystery reveal. A block that was *dealt* as a
		-- Bomb arms on impact instead, and by the time it settles that has already
		-- happened; a revealed one has no impact left to wait for.
		armBomb(block)
	end
end

-- Mystery blocks: dealt as a question mark, and only on landing does anyone find
-- out what they were holding. The whole piece is a bluff — you place it exactly
-- as carefully as you'd place the worst thing it could be.
--
-- The reveal is a fresh name plate plus a re-tint of the Highlight, because the
-- original plate has already been dismissed by the time this runs (that happens
-- on the first settle, above). Physics types are excluded from the pool: an
-- Anvil reveal would be a word with no event behind it, since the block has
-- already fallen at ordinary weight.
local function revealMystery(block: Block)
	local revealed = BlockTypes.rollMystery()
	if revealed == nil then
		return
	end
	block.blockType = revealed

	local highlight = block.model:FindFirstChild(TYPE_TELL_NAME)
	if highlight and highlight:IsA("Highlight") then
		highlight.FillColor = revealed.tell
		highlight.OutlineColor = revealed.tell
	end

	BlockLabel.attach(
		block.model,
		block.root,
		BlockLabel.titleFor(revealed.name, if block.shape then block.shape.name else nil),
		revealed.description
	)
	task.delay(Constants.MYSTERY_REVEAL_SECONDS, function()
		if block.model.Parent ~= nil then
			BlockLabel.dismiss(block.model)
		end
	end)

	applySettleEffect(block, revealed)
end

-- The types that resolve when the block comes to rest.
--
-- Bomb is deliberately absent: it resolves on *impact* (see `watchLanding`), and
-- one that reaches settle without having armed is one that landed too gently to
-- trigger it. Burning is absent for the opposite reason — it arrives already
-- alight, lit in `registerBlock`. The physics types (Bouncy, Anvil, Ice,
-- Feather) have nothing to resolve at all: their whole effect is the
-- PhysicalProperties they were built with.
local SETTLE_RESOLVED: { [string]: boolean } = {
	glue = true,
	clone = true,
	anchor = true,
	crate = true,
	mystery = true,
}

-- What a block does the moment it comes to rest. Everything here is once-only:
-- a block that gets knocked loose and re-settles must not glue itself twice or
-- hand the players a second clone.
local function onSettled(block: Block)
	if not block.settledOnce then
		block.settledOnce = true

		-- Closes the turn funnel for whoever dropped this. A turn that reaches
		-- "Dropped" and never reaches here is a piece that missed the tower
		-- entirely and fell past it, which is the difference between a player
		-- who is losing and a player who isn't playing.
		local placer = placerOf[block.model]
		if placer then
			AnalyticsService.step(placer, "turn", "Settled On Tower")
		end

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
	if block.resolved or blockType == nil or not SETTLE_RESOLVED[blockType.kind] then
		return
	end
	block.resolved = true

	-- Glue sets where the block ends up, not where it first grazed. Clone, Anchor
	-- and Crate wait for the same moment — the copy needs something solid to land
	-- on, and the other two have nothing to lock or break until the block has
	-- stopped moving.
	if blockType.kind == "mystery" then
		revealMystery(block)
		return
	end
	applySettleEffect(block, blockType)
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

-- Keep the streaming sphere centred on the live tower — the current floor up to
-- the top, which is everything that exists.
--
-- Read off `state` rather than re-walking the blocks: the poll has just written
-- both numbers, and centring on the span means each end sits half a stage's
-- climb from the focus instead of a whole one. Pieces spawn above the top and
-- debris flies past it; both are well inside the radius at that distance.
local function updateStreamingFocus()
	local part = streamingFocus
	if part == nil or part.Parent == nil then
		return
	end
	local floor = baseTopY + math.max(state.zoneBaseHeight, 0)
	-- `height` counts the current platform, so it's never below the floor — but
	-- it *is* zero for the first frames of a run, before the first poll lands.
	local top = baseTopY + math.max(state.height, state.zoneBaseHeight, 0)
	part.Position = Vector3.new(0, (floor + top) / 2, Constants.PLANE_Z)
end

local function updateHeight()
	-- The checkpoint cutscene and the round break each own the world while they
	-- run. Measuring a tower that's mid-demolition would spike the readout off
	-- flying debris and could clear the next stage from the wreckage of the last.
	if checkpointActive or intermission then
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
			CashService.award(climber, math.floor(gained * Constants.CASH_PER_STUD), "Height")
		end
	end

	-- Before updateStorm, which is what clears the stage: a tower that goes
	-- straight past 75% to the target should report passing 75% on the way,
	-- rather than having the checkpoint reset the marks out from under it.
	reportStageProgress(height)

	if updateStorm(height) then
		changed = true
	end

	-- Lift the held piece if the tower has grown under it since it spawned.
	if reseatHeldPiece(false) then
		changed = true
	end

	-- Re-send periodically even when nothing moved: a player who joined between
	-- broadcasts has no other way to learn the state.
	if changed or os.clock() - lastBroadcast > 1 then
		broadcast()
	end
end

-- ----------------------------------------------------------------- the turns --

-- The extra turn a Double Turn owner has coming, or nil for "read the queue".
--
-- The queue isn't touched for it: they were already rotated to the back when the
-- first of their turns was handed out, so their place in the rotation — and
-- everyone else's — is exactly where it was.
local function takeRepeatTurn(): Player?
	local again = repeatTurnFor
	if again == nil then
		return nil
	end

	repeatTurnsLeft -= 1
	if repeatTurnsLeft <= 0 then
		repeatTurnFor = nil
	end

	-- They left, opted out, or put the perk down between the two: the extra turn
	-- goes with them rather than stalling the queue on a player who isn't taking
	-- pieces. Re-read rather than remembered so the Settings toggle lands on the
	-- turn after it's flipped, not the rotation after.
	if
		again.Parent ~= Players
		or isSpectating(again)
		or SettingsService.get(again, Constants.SETTING_DOUBLE_TURN) == false
	then
		repeatTurnFor = nil
		return nil
	end
	return again
end

local function nextPlayer(): Player?
	local again = takeRepeatTurn()
	if again ~= nil then
		return again
	end

	-- Bounded by the queue length rather than `while #queue > 0`: a spectator is
	-- put back on the queue rather than dropped from it, so an unbounded loop
	-- would spin forever the moment everyone opted out.
	for _ = 1, #queue do
		local player = table.remove(queue, 1) :: Player
		if player.Parent ~= Players then
			continue
		end
		-- Back of the line, so the rotation is fair with any player count. A
		-- spectator keeps its place in the rotation — the setting takes them out
		-- of the turn order, not out of the room, and toggling it back on has to
		-- put them straight back in.
		table.insert(queue, player)
		if not isSpectating(player) then
			-- The Double Turn gamepass, and the owner's own switch on it: the
			-- perk can be put down from Settings, and that row only exists for
			-- owners in the first place. Checked here rather than trusted from
			-- the client for the same reason spectating is — a toggle only the
			-- client honoured wouldn't be a rule.
			--
			-- Not gated on there being anyone else in the server: alone, the
			-- queue is this player either way, so the pass simply doesn't show.
			if
				StoreService.ownsGamepass(player, Constants.GAMEPASSES.DOUBLE_TURN)
				and SettingsService.get(player, Constants.SETTING_DOUBLE_TURN) ~= false
			then
				repeatTurnFor = player
				repeatTurnsLeft = Constants.DOUBLE_TURN_TURNS - 1
			end
			return player
		end
	end
	-- Everyone is either gone or sitting out. The turn loop goes idle and the
	-- storm clock holds, which is the honest state for "nobody is playing".
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
	state.pieceTop = 0
	broadcast()
end

local function runTurns()
	while true do
		-- Nobody gets a piece while the checkpoint cutscene is playing, or while
		-- the round break is between the storm and the next round's first turn.
		while checkpointActive or intermission do
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
	-- character — which this game doesn't spawn. Without one, the player sees a
	-- live HUD over an empty sky.
	--
	-- Every player shares the one focus part, because every player is looking at
	-- the same tower. It rides the tower rather than sitting on the base: pinned
	-- to the base, the sphere stopped reaching the top of a tall run and the
	-- blocks up there simply stopped arriving. See `updateStreamingFocus`.
	if streamingFocus then
		player.ReplicationFocus = streamingFocus
	end
	-- Open this player's round and stage funnels at the step the room is
	-- actually on. Rounds outlive joins — most players arrive mid-run, and the
	-- server's very first round has no `runRoundBreak` behind it to announce
	-- itself — so without this their funnels would begin at whatever step
	-- happened next and every row would be missing its first step.
	AnalyticsService.start(player, "round", "Round Started")
	AnalyticsService.start(player, "stage", "Stage Started")

	-- The joiner's controller isn't listening yet; the 1s heartbeat in
	-- updateHeight is what actually gets them their first state.
	broadcast()
end

local function removePlayer(player: Player)
	local index = table.find(queue, player)
	if index then
		table.remove(queue, index)
	end
	-- A leaver's extra turn goes with them. `takeRepeatTurn` would drop it
	-- anyway; clearing it here is what keeps the strip from badging a player who
	-- isn't in the room.
	if repeatTurnFor == player then
		repeatTurnFor = nil
		repeatTurnsLeft = 0
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
	state.stormEndsAt = workspace:GetServerTimeNow() + stage.stormSeconds

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
		updateLightning()
		clampToPlane(deltaTime)
	end)

	task.spawn(function()
		while true do
			task.wait(Constants.POLL_INTERVAL)
			updateHeight()
			-- Outside updateHeight on purpose: that returns early through a
			-- checkpoint or a round break, and the streaming focus has to keep
			-- tracking through both — the demolition and the wreck are the parts
			-- of the game most worth actually seeing.
			updateStreamingFocus()
		end
	end)

	task.spawn(runTurns)
end

return TowerService
