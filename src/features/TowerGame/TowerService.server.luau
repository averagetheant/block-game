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
--
-- Two games live in here, and only the smaller half is shared. The classic game
-- above is one tower, one queue, one storm. PVP (`PvpService`) is six towers on
-- their own platforms with no turns at all — and it runs on this file's *block
-- engine*: `dealPiece`, `dropPiece`, `applyPlacement`, `laneHeight`, `clearLane`
-- and everything they reach, all of which take a lane rather than assuming the
-- one at the origin. See the "block engine API" section near the bottom.
--
-- What made that split cheap is that a block's behaviour was never about the
-- tower it was in. Bombs, fires, glue, ghosts and the plane clamp are all
-- spatial, so six towers set far enough apart need no rules the one tower didn't
-- already have. `laneX` is only ever read to *measure* — never to decide what a
-- block does.

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
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
local CheckpointQuestService = require(script.Parent.CheckpointQuestService)
local PlatformLayouts = require(script.Parent.PlatformLayouts)
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
	-- Which lane this block belongs to, as the lane's centre X. 0 for the classic
	-- game, which is one lane shared by the whole room; one of `PvpLanes.xOf`'s
	-- seats during a PVP round.
	--
	-- It's only ever read to *measure* — "how tall is this lane" and "what may a
	-- piece spawned here land on". Nothing about how a block behaves is filtered
	-- by it, because nothing needs to be: every hazard in the game is already
	-- spatial (a blast has a radius, a fire spreads by contact, glue welds what
	-- it's touching), and lanes are set far enough apart that none of them can
	-- reach the next one. That is the whole reason PVP could be built on this
	-- block engine rather than beside it.
	laneX: number,
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
	-- The fire this block belongs to, shared by every block in the same chain.
	-- It's what carries the spread budget from the block that started it to the
	-- ones it passes to, so the cap is on the fire rather than on each block.
	fire: BurnFire?,
}

-- One fire: everything lit from the same original block. Held by reference so a
-- spread anywhere in the chain spends from the one budget.
type BurnFire = {
	spreadsLeft: number,
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
	-- The lane this piece is being aimed over, and the floor it will eventually
	-- come down on if it misses everything. Both are fixed for the piece's whole
	-- turn: the holder owns X *within* the lane, never which lane they're in.
	laneX: number,
	floorY: number,
}

local TowerService = {}

-- Gameplay band: after PlayerData (1) / Notes (5), before leaf services.
TowerService.Priority = 20

local PHASE = Constants.PHASE

-- The classic game is one lane, and it's the one at the arena's origin. Named
-- rather than written as a bare 0 wherever a lane is asked for, so the classic
-- paths read as "the shared lane" instead of as an unexplained coordinate.
local CLASSIC_LANE = 0

local arena: Folder
-- The base's slabs and where each of them hangs when it's on the board.
--
-- A list rather than one part because the base is stamped out of a *layout* now
-- (see PlatformLayouts) and a layout is one or more slabs — Split is two with a
-- gap down the middle. The parent is kept per slab because a PVP match takes the
-- base off the board (see `setBaseOnBoard`) and has to put it back exactly where
-- it was, and a Studio-authored base is tagged rather than parented by us, so it
-- may live anywhere.
--
-- Note the base is deliberately *not* in `platforms`: that list is the checkpoint
-- floors, and everything in it is demolished when the next floor lands.
local baseSlabs: { { part: BasePart, parent: Instance? } } = {}
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
-- have no physics but still count toward the tower's top. Classic only: a PVP
-- lane has one platform, it never moves, and PvpService owns it — which is why
-- `restingTopY` takes the floor it should measure from as an argument rather
-- than assuming this list holds it.
local platforms: { BasePart } = {}
-- Every piece anyone is aiming right now, keyed by its holder.
--
-- Classic deals one piece at a time, so this holds at most one entry; a PVP
-- round gives every lane a piece of its own, so it holds one per player. Keying
-- by player rather than keeping a single slot is what let the two modes share
-- one held-piece lifecycle: `dealPiece`, `applyPlacement`, `reseatPiece` and
-- `dropPiece` are the same code either way, and only *who asks* differs.
local heldBy: { [Player]: Held } = {}
-- Whose piece the classic turn loop is currently waiting on, or nil between
-- turns. PVP never writes it — its lanes each run their own clock, and there is
-- no such thing as "the" holder.
local turnHolder: Player? = nil

-- The piece the classic turn loop is waiting on, or nil when nobody is up.
local function classicHeld(): Held?
	local player = turnHolder
	return if player ~= nil then heldBy[player] else nil
end

-- True while a PVP round has the board (see `runRoundBreak`). Everything the
-- classic game runs on a clock — the turn queue, the storm, the height readout,
-- the lightning — parks for the duration; everything that keeps *blocks* honest
-- — settling, burning, the plane clamp, the despawn sweep — keeps running,
-- because those belong to the blocks rather than to the mode.
local pvpActive = false

-- PvpService, required on first use rather than at the top of the file.
--
-- The dependency runs the other way for everything that matters: PVP borrows
-- this file's block engine (`dealPiece`, `dropPiece`, `laneHeight`) and this file
-- knows one thing about PVP — that a round can be handed to it. Naming it up
-- there would be a require cycle; by the time a round break can run, both modules
-- have long since loaded.
local pvpService: any = nil
local function pvp(): any
	if pvpService == nil then
		pvpService = require(script.Parent.PvpService)
	end
	return pvpService
end

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
-- Standing override for how often a piece is special, set by the "blockrate"
-- cmdr command. Unlike the one-shot above this holds until it's cleared, and it
-- outranks the stage's own number so it can't be undone by a checkpoint.
local devBlockTypeChance: number? = nil
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

-- ------------------------------------------------------------------ idleness --
-- A stage is one shared budget of about eighteen turns, and a player who isn't
-- there spends theirs dropping the piece from where it spawned. These three
-- track that so the clock can be handed back (a turn nobody touches ends early)
-- and so the room stops dealing turns to an empty chair (two in a row and they
-- take the "Not playing" seat until they say otherwise).
--
-- "Touched" is steering or rotating — the same test that decides whether a turn
-- counts as Steered / Rotated for the funnel. Holding the piece still for the
-- full clock is a decision, but it isn't one that needs fifteen seconds.
local heldTouched = false
-- When the current turn began, so granting the full clock on first touch is
-- measured from the start of the turn rather than from the moment they woke up.
local turnStartedAt = 0
-- Consecutive untouched turns, per player. Cleared the moment they touch a
-- piece, and on the way into the "Not playing" seat.
local idleTurns: { [Player]: number } = {}
-- Turns dealt to each player this session, so a first-timer's first turn can be
-- exempt from the short clock (IDLE_GRACE_TURNS).
local turnsDealt: { [Player]: number } = {}

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
	-- `stormSeconds` isn't mirrored here: it grows with the stage count, so
	-- `restartStormClock` owns it. Every applyStage call is followed by one.
end

-- Park the storm clock at a full stage, for as long as the poll keeps calling it.
--
-- `stormEndsAt` is an absolute server time and the HUD draws the bar as the
-- distance from now to it, so a clock that is merely *not read* still drains on
-- screen. Not reading it is what stops the storm firing; this is what stops it
-- looking like it's about to. Without it a PVP match and the ballot after it
-- handed the next classic round a bar that had spent both counting down — the
-- storm was never going to arrive, and every player watching it saw a minute
-- left on a round that hadn't started.
--
-- `state.stormSeconds` rather than the gamemode's, so a stage reached deep into a
-- run is held at its own grown length rather than snapping back to the first
-- stage's.
local function holdStormClock()
	state.stormEndsAt = workspace:GetServerTimeNow() + state.stormSeconds
end

-- Start the current stage's clock, and publish how long it runs.
--
-- The length grows with the floors already cleared, matching the gap growing
-- under STORM_GAP_GROWTH — a stage that asks for a longer climb is given the
-- turns to build it. The two numbers are set together because the HUD's storm
-- bar is `stormEndsAt` drawn as a fraction of `stormSeconds`, and a bar whose
-- ends disagree fills wrong for a whole stage.
--
-- Called on every path that starts a stage: a fresh run, a cleared checkpoint,
-- and the round break once the vote is in. Not by `extendStorm`, which pushes
-- the deadline out without lengthening the stage it belongs to.
local function restartStormClock()
	state.stormSeconds = stage.stormSeconds + state.checkpoints * Constants.STORM_TIME_GROWTH
	holdStormClock()
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

-- Exported because PVP has to answer the same question about the same setting,
-- and two readings of "is this player sitting out" that could disagree is two
-- bugs waiting — including the solo carve-out above, which is easy to forget and
-- soft-locks whoever forgets it.
TowerService.isSpectating = isSpectating

-- Book-keeping at the end of a turn: did they touch the piece, and if they
-- haven't for IDLE_TURNS_BEFORE_AFK turns running, take them out of the
-- rotation and tell them why.
--
-- Being taken out is the ordinary "Not playing" setting rather than a second,
-- parallel notion of benched. That's what makes the way back free: the toggle
-- in the Settings window and the card's own button are the same write, the
-- queue already honours it (`isSpectating` above), and the room needs no new
-- rule to understand the state.
--
-- Alone in the server, none of this runs. `isSpectating` already refuses to
-- bench a solo player — the queue would be empty and the game would stop — so
-- flipping the setting there would do nothing except leave them a card about a
-- rotation they aren't in.
local function noteTurnIdleness(player: Player, autoDropped: boolean)
	-- Two ways to prove you're there, and dropping the piece is the stronger one.
	--
	-- Steering was the only test at first, which quietly libelled anyone who
	-- plays by dropping the piece where it spawns: a straight drop down the middle
	-- is a placement, often the right one, and it moves nothing. Two of those in a
	-- row and the game benched a player who was taking their turns. `autoDropped`
	-- is false whenever `held` went nil on its own — the player's own Release —
	-- so pressing drop counts however still the piece was.
	--
	-- It's also false when a checkpoint takes the piece mid-turn, which reads as
	-- presence the player didn't demonstrate. That's the harmless direction: the
	-- cost of being wrong here is one un-benched idle turn, against a player who
	-- has to press a button to keep playing.
	if heldTouched or not autoDropped then
		idleTurns[player] = 0
		return
	end

	local missed = (idleTurns[player] or 0) + 1
	idleTurns[player] = missed

	if missed < Constants.IDLE_TURNS_BEFORE_AFK or #Players:GetPlayers() <= 1 then
		return
	end
	if SettingsService.get(player, Constants.SETTING_NOT_PLAYING) == true then
		return
	end

	-- The card is only sent if the bench actually took. A profile that hasn't
	-- loaded can't be written to, and announcing a benching that didn't happen is
	-- worse than staying quiet: the player reads that they're out, presses "I'm
	-- here!" to fix a state they were never in, and their turns keep arriving
	-- either way. Leaving the counter alone means the next idle turn tries again.
	if not SettingsService.set(player, Constants.SETTING_NOT_PLAYING, true) then
		return
	end

	-- Counted from zero rather than left at the limit: if they come back, play a
	-- turn and wander off again, that's a fresh two turns before this fires
	-- again rather than a single missed turn benching them.
	idleTurns[player] = 0

	-- Remembered so their next visit starts with them in the game. The setting
	-- persists, which is right for a player who chose it and a trap for one who
	-- was away — see PlayerData.luau.
	TowerStatsService.setAutoAfk(player, true)
	Packets.AfkNotice.sendTo({ turns = missed }, player)
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

-- The ground the run starts on, and the altitude a height of 0 means.
--
-- Three answers, in order of how much the place has asked for:
--
--   1. A part tagged BASE_TAG. Someone built their own base in Studio and this
--      file's opinion is not wanted — including its opinion about layouts.
--   2. A layout eligible for floor 0 (see PlatformLayouts). This is where Split
--      and the rest come in, and it's why a run doesn't always open on a slab.
--   3. The generated prototype slab, so the game is playable in an empty place.
--
-- Returns the slabs and the scoreline. The scoreline is the layout's *pivot*,
-- not the top of whichever slab happens to be highest: the author decides which
-- surface is the ground, which is what lets a layout have a wall above it or a
-- pit below it without either one moving the score.
local function buildBase(): ({ BasePart }, number)
	for _, tagged in CollectionService:GetTagged(Constants.BASE_TAG) do
		if tagged:IsA("BasePart") then
			-- Adopted, not built — so the two things a floor cannot be wrong about
			-- are asserted here rather than trusted. A stock Studio part is
			-- unanchored with plastic physics (friction 0.3, elasticity 0.5), which
			-- is a floor that both falls away and bounces what lands on it.
			-- Everything else about the part is the author's: size, position,
			-- colour, material, whatever they hung off it.
			tagged.Anchored = true
			tagged.CustomPhysicalProperties = Constants.FLOOR_PHYSICS
			return { tagged }, tagged.Position.Y + tagged.Size.Y / 2
		end
	end

	-- Where the prototype slab's top surface has always sat, so a layout base and
	-- a generated base put the ground at the same altitude and a map built around
	-- the arena works with either.
	local floorY = Constants.BASE_POSITION.Y + Constants.PLATFORM_SIZE.Y / 2

	local layout = PlatformLayouts.pick("base", 0)
	if layout then
		return PlatformLayouts.build(layout, floorY, arena, "Base"), floorY
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
	-- The ground decides its own contacts; see FLOOR_PHYSICS.
	part.CustomPhysicalProperties = Constants.FLOOR_PHYSICS
	part.Parent = arena
	CollectionService:AddTag(part, Constants.BASE_TAG)
	return { part }, floorY
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

	local slabs, floorY = buildBase()
	baseSlabs = {}
	for _, slab in slabs do
		table.insert(baseSlabs, { part = slab, parent = slab.Parent })
	end
	baseTopY = floorY
	-- Published for the client camera; see Constants.BASE_TOP_ATTRIBUTE.
	arena:SetAttribute(Constants.BASE_TOP_ATTRIBUTE, baseTopY)

	streamingFocus = buildStreamingFocus()
end

-- Take the classic base off the board, or put it back.
--
-- A PVP match builds a platform per lane and the base belongs to none of them: it
-- stands at `x = 0`, which with symmetric seats is the gap between slots 2 and 3
-- — a seventh slab, at lane altitude, that nobody is building on and that the map
-- shot frames along with the towers. So the mode that doesn't use it doesn't have
-- it.
--
-- Parented away rather than made invisible, so it takes its shadow, its
-- collisions and anything a map-builder has hung off it with it. It's the same
-- part on the way back, tag and all, so a Studio-authored base survives a match
-- unchanged.
--
-- `baseTopY` is deliberately untouched. It's the altitude a height of 0 means,
-- the lanes are built at that same altitude (`PvpConstants.LANE_Y`), and every
-- client's camera reads it off the arena attribute for the whole match — so the
-- number has to outlive the part.
local function setBaseOnBoard(onBoard: boolean)
	for _, slab in baseSlabs do
		slab.part.Parent = if onBoard then slab.parent else nil
	end
end

-- --------------------------------------------------------------- the pieces --

-- Sounds live on the piece itself so they're positional and replicate with it —
-- the server calls :Play() and every client hears it from the right place.
--
-- Block-only, which is why BLOCK_VOLUME_SCALE is applied in here rather than at
-- the two call sites: every Sound this function has ever made hangs off a block.
local function attachSound(part: BasePart, name: string, soundId: string, volume: number): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = soundId
	sound.Volume = volume * Constants.BLOCK_VOLUME_SCALE
	sound.RollOffMaxDistance = Constants.SOUND_RANGE
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.Parent = part
	return sound
end

-- A cue coming out of a block: the drop, the glue weld, the bomb's beep, and the
-- landing sample for a type that owns its own.
--
-- Wrapped rather than calling `Sfx.playAt` directly so BLOCK_VOLUME_SCALE lands
-- on all of them from one place. `Sfx.playAt` itself stays honest about what it
-- is — a positional one-shot on any part — because the day something that isn't
-- a block wants one, it should not inherit the block mix.
local function playAtBlock(cue: string, part: BasePart, volumeScale: number?)
	Sfx.playAt(cue, part, (volumeScale or 1) * Constants.BLOCK_VOLUME_SCALE)
end

-- A fresh colour per piece. Random hue at a fixed saturation and value, rather
-- than a random RGB triple, so every block is vivid and none come out muddy or
-- washed out against the sky.
local function randomColor(): Color3
	return Color3.fromHSV(math.random(), 0.68, 0.98)
end

local function collectParts(model: Model): { BasePart }
	local found = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(found, descendant)
		end
	end
	return found
end

-- Every BasePart of a model, descendants included. Pieces built here are flat
-- (cells are direct children), but a Noob rig hangs a Handle inside every
-- accessory, and an anchored hat on an unanchored rig floats where it was.
--
-- The rounded body a block is seen as never appears here, because it never exists
-- on this side: each client builds its own over these cubes and mirrors whatever
-- this file does to them. That's the whole reason the body is client-built —
-- besides being the only way it renders — it means nothing in the simulation has
-- to know it exists.
local function modelParts(model: Model): { BasePart }
	return collectParts(model)
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

-- Collision groups exist for exactly one thing: letting a Ghost fall through the
-- tower without falling through the world. Every block goes in one group, the
-- base and the checkpoint platforms stay in Default, and a ghost sits in a group
-- that ignores the first and still lands on the second.
--
-- Registering is idempotent-by-pcall rather than by asking: the groups persist in
-- the place once created, so a second server start (or a Studio session that has
-- already run one) would otherwise error on a name that's simply already there.
local function ensureCollisionGroups()
	for _, name in { Constants.BLOCK_COLLISION_GROUP, Constants.GHOST_COLLISION_GROUP } do
		pcall(function()
			PhysicsService:RegisterCollisionGroup(name)
		end)
	end
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(
			Constants.GHOST_COLLISION_GROUP,
			Constants.BLOCK_COLLISION_GROUP,
			false
		)
	end)
end

local function setCollisionGroup(model: Model, group: string)
	for _, part in modelParts(model) do
		part.CollisionGroup = group
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

-- The second, fainter Highlight a block wears once something has been glued to
-- it. Its own name so it can't be confused with the type tell above — a block can
-- carry both, and the Mystery reveal re-tints only the one it owns.
local GLUE_TELL_NAME = "GlueTell"
-- What one wears when the gluing block can't say (a Cmdr-forced glue with the
-- type stripped, say). The real colour comes off the block doing the gluing —
-- see `markGlued` — so the two always read as one thing.
local GLUE_TELL_FALLBACK = Color3.fromRGB(126, 240, 138)

-- The tiled pattern a skin can wear over its material (Duck's, and only Duck's).
-- Named so it's findable in the explorer; the client mirrors these onto the
-- rounded body by class rather than by name, so nothing depends on the string.
local SKIN_TEXTURE_NAME = "SkinTexture"

-- Dress a cell in the skin's texture, if it has one.
--
-- All six faces, because a block is seen from every side as the tower turns and
-- a pattern that stopped at the silhouette would read as a bug. Tiled at exactly
-- one tile per cell face rather than stretched: a piece is one to four cells
-- depending on the shape, and stretching would make the pattern a different size
-- on an I than on an O.
--
-- A Texture rather than the material itself, so the hue roll underneath still
-- comes through and every effect that repaints a block — a bomb's red flash, a
-- burn charring it — keeps working with nothing written for it here.
local function applySkinTexture(part: BasePart, skin: BlockSkins.Skin)
	local id = skin.texture
	if id == nil then
		return
	end
	for _, face in Enum.NormalId:GetEnumItems() do
		local texture = Instance.new("Texture")
		texture.Name = SKIN_TEXTURE_NAME
		texture.Texture = id
		texture.Face = face
		texture.StudsPerTileU = Constants.BLOCK_SIZE
		texture.StudsPerTileV = Constants.BLOCK_SIZE
		texture.Parent = part
	end
end

-- `color` names the shade instead of rolling one. Only the Clone type passes it:
-- a copy has to come out the colour of the block it copied, and every other caller
-- wants a fresh shade.
local function buildPiece(
	shape: Shapes.Shape,
	skin: BlockSkins.Skin,
	blockType: BlockTypes.BlockType?,
	pack: SkinPacks.SkinPack?,
	color: Color3?
): (Model, BasePart, Color3)
	local model = Instance.new("Model")
	model.Name = `Piece_{shape.name}`
	-- The skin keeps its material and its sounds; only the colour is rolled. A
	-- colour pack rolls within its own family instead of across the whole wheel
	-- — still a fresh shade per block, so the pieces stay legible as separate
	-- blocks rather than merging into one flat mass.
	local color = color or SkinPacks.colorFor(pack) or randomColor()

	-- A colour pack sets no material, so the rolled skin's own surface (and its
	-- sounds) survive underneath the tint.
	local material = if pack and pack.material then pack.material else skin.material
	local transparency = skin.transparency or 0

	-- The cells are the *collision*, and they stay square: a rounded collision
	-- shape would settle into its neighbours' corners and a flat course would stop
	-- being flat.
	--
	-- They also stay **visible**, and the rounded body the player actually sees is
	-- built over them by each client (see TowerBodyController). The body used to be
	-- made here and welded on, which worked in every measurement and rendered as a
	-- tiny cube on the client — a server-made CSG union is data the client has
	-- (right Size, right triangle count) and still won't draw. The client's own
	-- clone of the same asset draws perfectly, which is what the aim preview has
	-- always done, so the body is now built where it renders.
	--
	-- Leaving the cubes visible is the fallback rather than a compromise: a client
	-- that can't build a body shows the block the game had before bodies existed,
	-- and the server view stays readable for debugging.
	local root: BasePart? = nil
	for index, cell in shape.cells do
		local cube = Instance.new("Part")
		cube.Name = `Cell{index}`
		cube.Size = Vector3.new(Constants.BLOCK_SIZE, Constants.BLOCK_SIZE, Constants.BLOCK_DEPTH)
		cube.Color = color
		cube.Material = material
		cube.Transparency = transparency
		cube.TopSurface = Enum.SurfaceType.Smooth
		cube.BottomSurface = Enum.SurfaceType.Smooth
		cube.CustomPhysicalProperties = Constants.BLOCK_PHYSICS
		cube.Anchored = true
		cube.CFrame =
			CFrame.new(cell.X * Constants.BLOCK_SIZE, cell.Y * Constants.BLOCK_SIZE, Constants.PLANE_Z)
		applySkinTexture(cube, skin)
		cube.Parent = model
		if root == nil then
			root = cube
		end
	end

	local rootPart = root :: BasePart
	-- Stamped at build time, not just at `registerBlock`: a piece is parented into
	-- the arena as the *held* piece and only registers when it's released, so a
	-- client reading the skin off a freshly-parented model would find nothing and
	-- fall back to a default for the block's whole fall.
	model:SetAttribute(Constants.SKIN_ATTRIBUTE, skin.id)
	-- Which rounded body each client should build over these cubes. An attribute
	-- rather than a packet for the same reason the skin is one: it has to arrive
	-- with the block and stay attached to it for the block's whole life, including
	-- on the clone the aim preview makes of it.
	model:SetAttribute(Constants.SHAPE_ATTRIBUTE, shape.id)
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
--
-- Measured per lane. The classic game is one lane (`laneX` 0) shared by
-- everyone; a PVP round is one lane per player, and a piece has to clear its own
-- tower rather than the tallest tower on the board. `floorY` is what the lane
-- stands on — the arena base in classic, the lane's own platform in PVP — so
-- this needs no opinion about which of those it's looking at.
local function restingTopY(laneX: number, floorY: number): number
	local top = floorY
	for _, block in blocks do
		if block.laneX ~= laneX or block.root.Parent == nil then
			continue
		end
		if not (block.custom or block.settled or block.slowSince ~= nil) then
			continue
		end
		for _, part in modelParts(block.model) do
			top = math.max(top, partTopY(part))
		end
	end
	-- Checkpoint platforms belong to the classic game, which is lane 0. A PVP
	-- lane's floor arrives as `floorY` instead, so this loop is skipped rather
	-- than handing every lane the altitude of a checkpoint standing at x = 0.
	if laneX == CLASSIC_LANE then
		for _, platform in platforms do
			top = math.max(top, partTopY(platform))
		end
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
local function clearPivotY(laneX: number, floorY: number, halfHeight: number): number
	return restingTopY(laneX, floorY) + halfHeight + Constants.SPAWN_CLEARANCE
end

-- Where a fresh piece appears: over its own lane, clear of whatever has been
-- built in it. Pieces always spawn on the lane's centre line — the holder owns X
-- from there, and starting them anywhere else would make "centred" mean
-- something different for every player.
local function spawnPivot(laneX: number, floorY: number, halfHeight: number): CFrame
	return CFrame.new(laneX, clearPivotY(laneX, floorY, halfHeight), Constants.PLANE_Z)
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
local function reseatPiece(piece: Held, down: boolean): boolean
	local wanted = clearPivotY(piece.laneX, piece.floorY, piece.halfHeight)
	local shift = wanted - piece.pivot.Position.Y
	if math.abs(shift) < Constants.HEIGHT_EPSILON then
		return false
	end
	if shift < 0 and not down then
		return false
	end

	piece.pivot = piece.pivot + Vector3.new(0, shift, 0)
	piece.model:PivotTo(piece.pivot)
	return true
end

-- How high the top of a piece sits above the floor it was dealt over. The number
-- the camera frames against, in the same terms as the lane's height.
local function pieceTopOf(piece: Held): number
	return piece.pivot.Position.Y + piece.halfHeight - piece.floorY
end

TowerService.pieceTopOf = pieceTopOf

-- The classic wrapper: reseat the one piece the turn loop is watching, and keep
-- the broadcast number in step with it.
local function reseatHeldPiece(down: boolean): boolean
	local piece = classicHeld()
	if piece == nil or not reseatPiece(piece, down) then
		return false
	end
	state.pieceTop = pieceTopOf(piece)
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

	-- A statue is scenery, which is the same argument from the other end: an
	-- Anchor block has been turned to stone (`petrify`) and is never moving again,
	-- so there's no skin left to re-dress and no physics left to matter. Without
	-- this the next zone change would hand it its old material back and the stone
	-- would last until the weather turned.
	if model:GetAttribute(Constants.STATUE_ATTRIBUTE) then
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

	-- Cells only, because cells are all the server has: the rounded body is built
	-- by each client over the top of these, and it mirrors what it finds here — so
	-- dressing the cubes correctly is what dresses the block. Retro's studs are the
	-- clearest case: the client reads them off a cell and takes the rounded body
	-- off, because studs render as nothing on a rounded face.
	for _, part in modelParts(model) do
		if retro then
			part.Material = Enum.Material.Plastic
			setSurfaces(part, Enum.SurfaceType.Studs)
		else
			part.Material = if pack and pack.material then pack.material else skin.material
			setSurfaces(part, Enum.SurfaceType.Smooth)
		end
		part.CustomPhysicalProperties = physics
		-- A textured skin steps aside under Retro for the same reason the rounded
		-- body does: studs and a tiled pattern on the same face are two looks
		-- fighting, and the zone's is the one that's meant to win. Only reachable
		-- when the skin arrived without its pack — a pack that pins a skin owns the
		-- surface, so `retro` is already false for a real Duck block — but the cmdr
		-- `skin` command can put one there, and that shouldn't look broken.
		for _, texture in part:GetChildren() do
			if texture:IsA("Texture") then
				texture.Transparency = if retro then 1 else 0
			end
		end
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
	-- Every piece in the air, which is one in classic and one per lane in PVP.
	for _, piece in heldBy do
		applyZoneLook(piece.model, piece.skin, piece.blockType, piece.pack)
	end
end

-- Back to clear skies and default gravity, re-dressing whatever is standing.
--
-- Two paths hand the world to a classic round that hasn't started yet — the end
-- of a run and the end of a PVP match — and neither may hand it back wearing the
-- last one's weather.
local function restoreDefaultZone()
	state.zoneId = Zones.DEFAULT_ID
	state.zoneSky = math.random(1, 255)
	applyZoneToTower()
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

-- `x` is measured from the holder's own lane centre, not from the world origin.
-- In classic those are the same point; in PVP they are up to three hundred studs
-- apart, and lane-relative is the only version of the number a client can be
-- trusted with — the clamp below is then the same clamp in both modes, and a
-- player cannot aim into somebody else's lane by sending a bigger number.
function TowerService.applyPlacement(player: Player, x: number, turns: number)
	local piece = heldBy[player]
	if piece == nil then
		return
	end
	-- NaN survives math.clamp and would poison the pivot, so reject it here.
	if x ~= x then
		return
	end

	local clampedX = math.clamp(x, -Constants.STEER_LIMIT_X, Constants.STEER_LIMIT_X)
	local quarter = math.floor(turns) % 4

	piece.pivot = CFrame.new(piece.laneX + clampedX, piece.pivot.Position.Y, Constants.PLANE_Z)
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

	-- First sign of life this turn: hand back the rest of the clock.
	--
	-- The turn opened on IDLE_TURN_SECONDS, and this is what makes that safe —
	-- the short window is only ever spent by someone who isn't aiming, and the
	-- moment they are, they have the whole of it. `turnEndsAt` is a server-time
	-- stamp the HUD's dial counts down from, so the extension replicates as more
	-- time on the ring rather than as a dial that has to be told it lied.
	if heldTouched or (math.abs(clampedX) <= 1 and quarter == 0) then
		return
	end
	heldTouched = true
	idleTurns[player] = 0
	state.turnEndsAt = turnStartedAt + stage.turnSeconds
	broadcast()
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
	-- A type may own the landing outright (`BlockTypes.impactCue`), and the Anvil
	-- does: what it lands on is the point of it, and a five-ton block landing on a
	-- grass footstep is the joke told wrong. Played *instead of* the skin's sample
	-- rather than over it — two impacts on the same frame read as a stutter, not
	-- as weight.
	--
	-- Through the cue library rather than the block's own Sound, because it's a
	-- Sound a human tuned in Studio: `playAt` clones it with that tuning and the
	-- landing speed scales it, the same way the skin's own sample is scaled below.
	local blockType = block.blockType
	local cue = if blockType then blockType.impactCue else nil
	if cue ~= nil then
		playAtBlock(cue, block.root, (0.35 + 0.65 * loudness) * Constants.IMPACT_VOLUME_SCALE)
		return
	end

	-- A fresh take per landing for a skin that has a folder of them; the same id
	-- back for one that doesn't, which makes this a no-op write. Pitch alone
	-- isn't enough variety at this repetition rate — the ear catches a repeated
	-- *sample* long before it catches a repeated pitch, and a tower is forty
	-- landings of the same material.
	sound.SoundId = BlockSkins.impactIdFor(block.skin)

	local range = block.skin.pitchRange
	-- Overwrites what `attachSound` set, so the scale has to be re-applied here —
	-- this is the same Sound, re-tuned for how hard this particular landing was.
	sound.Volume = block.skin.volume
		* Constants.BLOCK_VOLUME_SCALE
		* Constants.IMPACT_VOLUME_SCALE
		* (0.35 + 0.65 * loudness)
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
-- The mark a glued block wears for the rest of the run.
--
-- Glue is the only effect in the game whose result is *invisible*: the welds are
-- real and permanent, and the only way to find out which blocks were caught in
-- the cluster was to knock the tower and see what refused to move. This is that
-- answer, drawn on the blocks themselves.
--
-- Idempotent by name — a block glued twice, or glued by two different pieces,
-- wears one mark rather than a stack of them.
--
-- `tell` is the gluing block's own colour, handed down rather than looked up, so
-- the piece that did it and the blocks it did it to are the same green by
-- construction — including when a Mystery turns out to have been Glue.
local function markGlued(model: Model, tell: Color3)
	if model:FindFirstChild(GLUE_TELL_NAME) then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = GLUE_TELL_NAME
	highlight.FillColor = tell
	highlight.OutlineColor = tell
	highlight.FillTransparency = Constants.GLUE_TELL_TRANSPARENCY
	highlight.OutlineTransparency = Constants.GLUE_TELL_OUTLINE_TRANSPARENCY
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model
end

local function glueBlock(block: Block)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { block.model }

	-- Collected as a set and marked after the sweep, because the box overlap
	-- returns *cells*: a four-cell neighbour comes back four times and would be
	-- marked four times, and an I-piece welded along its length four more.
	local glued: { [Model]: true } = {}

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

			-- Only blocks get marked. Glue welds to whatever it's touching, and
			-- that routinely includes the base and the checkpoint platform it's
			-- standing on — but those aren't in `blockByModel`, so "is it a block"
			-- and "is it not the floor" are the same question, answered once.
			--
			-- `blockByModel` directly rather than `blockOf`, which is a local
			-- declared further down the file and would still be nil here.
			local model = other:FindFirstAncestorOfClass("Model")
			local neighbour = if model then blockByModel[model] else nil
			if neighbour ~= nil and neighbour ~= block then
				glued[neighbour.model] = true
			end
		end
	end

	local blockType = block.blockType
	local tell = if blockType then blockType.tell else GLUE_TELL_FALLBACK
	for model in glued do
		markGlued(model, tell)
	end

	-- Once for the block, not once per weld: a piece settling against four
	-- neighbours would otherwise fire this four times on the same frame.
	playAtBlock("Glue", block.root)
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

-- One frame of a Magnet's field: everything in reach is dragged *toward* the
-- origin, with the same distance falloff a blast uses pointed the other way.
--
-- **A velocity write, not `ApplyImpulse`, and once per frame rather than once.**
-- Both departures come from the same failure. A blast lands on blocks that are
-- already moving or about to be; a Magnet lands on a tower that has been sitting
-- still for a minute, and a settled Roblox assembly is *asleep*. One impulse into
-- a sleeping stack is the whole effect, spent in a frame, against static friction
-- that erases it in a fifth of a second — which is why two rounds of raising the
-- number changed nothing anybody could see. Writing `AssemblyLinearVelocity` is
-- what reliably wakes an assembly, and re-applying it every frame for
-- MAGNET_SECONDS means friction has to be beaten continuously instead of once.
--
-- Accumulating velocity rather than setting it, so a block already moving is
-- steered rather than stopped, and so the field builds over its window instead of
-- teleporting anything on the first frame.
--
-- Anchored blocks are skipped outright (the Anchor type, the platforms, the
-- checkpoint floors): a Magnet must not drag the floor out from under anyone, and
-- an anchored part silently ignoring a velocity write is a coincidence to rely on
-- rather than a rule.
local function pullTick(origin: Vector3, radius: number, accel: number, deltaTime: number, exclude: Block?)
	for _, other in blocks do
		local root = other.root
		if root.Parent == nil or root.Anchored or other == exclude then
			continue
		end
		local offset = origin - root.Position
		local distance = offset.Magnitude
		-- The block sitting exactly on the origin has no direction to be pulled
		-- in, and `Unit` on a zero vector is NaN — which would poison the
		-- assembly's velocity rather than simply doing nothing.
		if distance > radius or distance < 1e-3 then
			continue
		end
		local falloff = 1 - distance / radius
		-- Normalised after the lift is added, so the bias tilts the pull rather
		-- than adding strength to it — the same shape `blastAt` uses. The lift is
		-- what unsticks a resting block instead of grinding it into the floor it
		-- sits on; because the tug is inward, what a lifted block does next is come
		-- down closer in.
		local direction = (offset.Unit + Vector3.new(0, Constants.MAGNET_LIFT, 0)).Unit
		root.AssemblyLinearVelocity += direction * accel * falloff * deltaTime
	end
end

-- A Magnet has *settled*: it holds a field for MAGNET_SECONDS, pulling the tower
-- in around it, and then it's an ordinary block forever.
--
-- The origin is re-read each frame rather than captured, so a magnet that gets
-- shoved while it's pulling drags its field along with it — the block is the
-- magnet, not the spot it landed on.
local function magnetiseBlock(block: Block)
	task.spawn(function()
		local elapsed = 0
		while elapsed < Constants.MAGNET_SECONDS do
			local deltaTime = task.wait()
			elapsed += deltaTime
			-- Burned, blasted, stormed or sacrificed in the meantime: the field goes
			-- with the block that was making it.
			if block.root.Parent == nil then
				return
			end
			pullTick(
				block.root.Position,
				Constants.MAGNET_RADIUS,
				Constants.MAGNET_ACCEL,
				deltaTime,
				block
			)
		end
	end)
end

-- The live block a part belongs to, or nil for anything that isn't one: the base,
-- a checkpoint platform, the wall, a sacrifice corpse on its way out. Everything
-- in the tower is a cell of some model, and `blockByModel` is the only list that
-- says which of those models the game is still keeping books on — which is what
-- makes "not a block" safe by construction rather than by enumeration.
local function blockOf(part: BasePart): Block?
	local model = part:FindFirstAncestorOfClass("Model")
	return if model then blockByModel[model] else nil
end

-- What a settled block is standing on: the nearest block under any of its cells,
-- within SACRIFICE_REACH of that cell's underside.
--
-- One ray per cell, from the cell's own centre straight down. Starting at the
-- centre rather than on the bottom face is deliberate — a ray that begins exactly
-- on a surface is free to miss it, and a settled block's underside is *touching*
-- the thing this is looking for. The block's own model is excluded, so starting
-- inside itself costs nothing.
--
-- Nearest wins, so a piece bridging two towers takes the one it's actually
-- resting on rather than whichever cell happened to be walked first. Anything the
-- ray hits that isn't a live block — the base, a checkpoint platform, the wall —
-- simply isn't in `blockByModel` and is therefore safe by construction.
local function blockUnder(block: Block): Block?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { block.model }

	local found: Block? = nil
	local nearest = math.huge

	for _, part in modelParts(block.model) do
		local reach = part.Size.Y / 2 + Constants.SACRIFICE_REACH
		local hit = workspace:Raycast(part.Position, Vector3.new(0, -reach, 0), params)
		if hit == nil or hit.Distance >= nearest then
			continue
		end
		local other = blockOf(hit.Instance)
		if other == nil or other == block then
			continue
		end
		found = other
		nearest = hit.Distance
	end

	return found
end

-- The visible half of a sacrifice: the block that was taken glows, drifts away
-- and fades out.
--
-- What flies away is a **copy**. The victim itself is destroyed on the same frame
-- it's hit, and that ordering is the whole trick: the moment a block is
-- sacrificed it has to stop being part of the tower — no collision, no height, no
-- weld dragging a glued neighbour after it, nothing for a bomb or a burn to find
-- — and a corpse that is still the real block is a block every one of those
-- systems can still see. Cloning keeps the removal exactly what it always was (a
-- Destroy) and leaves the animation as pure furniture: anchored, uncollidable,
-- unqueryable, in the arena for a second and then not.
--
-- It needs no telling to look right, either. Each client bodies any model in the
-- arena carrying a shape attribute (see TowerBodyController) and drives that body
-- from the cells' colour, material and transparency — the same route a burning
-- block chars and a ghost goes see-through by — so the corpse wears the shell the
-- block wore and this drives it from the server without knowing bodies exist.
local function playSacrificeFx(model: Model, away: Vector3)
	-- A Noob is a character rig rather than a tetromino, and a rag-doll corpse of
	-- one drifting up the screen is a different effect than the one being asked
	-- for here. It's taken without the send-off.
	if model:GetAttribute(Constants.SHAPE_ATTRIBUTE) == nil then
		return
	end

	local corpse = model:Clone()
	corpse.Name = Constants.SACRIFICE_CORPSE_NAME
	-- Everything that made it a block rather than a picture of one: the welds
	-- holding it to the tower, the sounds it would play on the way out, the type
	-- tell and the name plate.
	for _, descendant in corpse:GetDescendants() do
		if
			descendant:IsA("WeldConstraint")
			or descendant:IsA("Sound")
			or descendant:IsA("Highlight")
			or descendant:IsA("BillboardGui")
		then
			descendant:Destroy()
		end
	end

	-- Anchored, so no weld is needed to hold the cells together and no physics
	-- can touch them; every cell is moved by hand from the pivot below.
	local pivot = corpse:GetPivot()
	type Cell = { part: BasePart, offset: CFrame, color: Color3, transparency: number }
	local cells: { Cell } = {}
	for _, part in corpse:GetChildren() do
		if not part:IsA("BasePart") then
			continue
		end
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		table.insert(cells, {
			part = part,
			offset = pivot:Inverse() * part.CFrame,
			color = part.Color,
			transparency = part.Transparency,
		})
	end
	if #cells == 0 then
		corpse:Destroy()
		return
	end

	corpse.Parent = arena

	task.spawn(function()
		local elapsed = 0
		while elapsed < Constants.SACRIFICE_FADE_SECONDS do
			elapsed += RunService.Heartbeat:Wait()
			if corpse.Parent == nil then
				return
			end

			local t = math.clamp(elapsed / Constants.SACRIFICE_FADE_SECONDS, 0, 1)
			-- Glow first, go second. The flash is what says *this was taken* while
			-- the block is still solid enough to be recognised as the one that
			-- went; the fade is the leaving.
			local glow = math.clamp(elapsed / Constants.SACRIFICE_FLASH_SECONDS, 0, 1)
			local fade = math.clamp(
				(t - Constants.SACRIFICE_HOLD) / (1 - Constants.SACRIFICE_HOLD),
				0,
				1
			)
			-- Up, and away from whatever took it. Slow on purpose: this is a block
			-- being spent, and a corpse that shoots off reads as an explosion.
			local drift = (Vector3.new(0, Constants.SACRIFICE_RISE, 0) + away * Constants.SACRIFICE_DRIFT)
				* elapsed
			-- Spun about Z only. Every piece is axis-aligned in the play plane, so
			-- the piece's own Z is the world's, and a tumble on any other axis
			-- would turn the shape edge-on to the camera.
			local moved = CFrame.new(drift) * pivot * CFrame.Angles(0, 0, Constants.SACRIFICE_SPIN * elapsed)

			for _, cell in cells do
				local part = cell.part
				part.CFrame = moved * cell.offset
				part.Color = cell.color:Lerp(Constants.SACRIFICE_GLOW, glow)
				-- Measured from what the cell already wore: a skin can be
				-- translucent to begin with (Needoh is), and fading from 0 would
				-- make it briefly *more* solid on its way out.
				part.Transparency = cell.transparency + (1 - cell.transparency) * fade
			end
		end

		corpse:Destroy()
	end)
end

-- Sacrifice blocks: the block they hit is unmade, and they carry on into the hole
-- it leaves.
--
-- The only type whose effect is a *trade* rather than a hazard. Every other
-- special piece is something to survive; this one is a tool, and the tower it's
-- aimed at is usually your own — you spend a turn and a block you already built
-- to undo a placement the room regrets. Taking a badly wedged Anchor with it is
-- the best thing it does, and the reason anchored blocks aren't spared here: a
-- bomb can already clear one, so "locks itself in place" was never a promise
-- against demolition.
--
-- **Resolved on contact** (see `watchLanding`), which is what makes it a piece
-- you aim: the block it takes is the one it *hit*, so a Sacrifice steered into
-- the side of a stack takes the block it ran into rather than whatever it happens
-- to be resting on once it has tumbled to a stop. It fires once — the caller
-- latches `resolved` first — so a piece that drops through its own hole and hits
-- something else on the way doesn't eat the tower a floor at a time.
--
-- `victim` is nil only on the Mystery-reveal path, which has no impact left to
-- read: a piece that turns out to be a Sacrifice after it has already come to
-- rest takes what it's standing on (`blockUnder`), because that's the one honest
-- answer available that late.
--
-- Nothing to do when it hits the base, a checkpoint platform, or nothing at all
-- off the side: the sacrifice is spent and the piece is an ordinary block. A miss
-- is a real outcome for a piece you have to aim.
local function sacrificeBlock(block: Block, victim: Block?)
	local target = victim or blockUnder(block)
	if target == nil then
		return
	end

	local position = target.root.Position
	-- Which way the corpse leaves: away from the block that took it, flattened
	-- onto the play plane so it can't drift in front of the tower or behind it.
	-- A hit from directly underneath or dead on top leaves it going straight up.
	local sideways = position.X - block.root.Position.X
	local away = if math.abs(sideways) > 0.01 then Vector3.new(math.sign(sideways), 0, 0) else Vector3.zero

	-- On a marker at the victim's position rather than on either block: the target
	-- is about to be destroyed and would take a sound parented to it, and the
	-- sacrifice itself is still falling.
	Sfx.playAtPosition("Sacrifice", position, Constants.SACRIFICE_VOLUME)
	playSacrificeFx(target.model, away)
	-- Destroying the model is the whole removal: `sweepBlocks` drops the entry and
	-- the `blockByModel` mapping on its next pass, the same way a burnt-out block
	-- leaves the list. The corpse above is a copy and is not in either.
	target.model:Destroy()
end

-- A Ghost falls through the tower for GHOST_SECONDS and then turns solid
-- wherever it has got to. The transparency is saved per part rather than assumed:
-- skins already set their own (Needoh is squishy and translucent), and blanket
-- restoring to 0 would repaint a skin the player paid for.
--
-- Solidifying inside another block is a real outcome, not a bug to prevent — the
-- physics shoves the two apart and the tower lurches. That's the cost of a piece
-- that can be threaded into a gap it doesn't fit through: aim well and it's the
-- best block in the game, aim badly and you've put a wedge in your own tower.
local function startGhost(block: Block)
	-- Saved per part rather than assumed, because a block carries its skin's own
	-- transparency (Needoh is translucent) and a blanket restore to 0 would repaint
	-- a skin someone bought. Each client's rounded body mirrors these cells, so it
	-- goes see-through with them and needs no telling.
	local saved: { [BasePart]: number } = {}
	for _, part in modelParts(block.model) do
		saved[part] = part.Transparency
		part.Transparency = Constants.GHOST_TRANSPARENCY
	end
	setCollisionGroup(block.model, Constants.GHOST_COLLISION_GROUP)

	task.delay(Constants.GHOST_SECONDS, function()
		-- Burned, blasted or stormed away in the meantime.
		if block.model.Parent == nil then
			return
		end
		setCollisionGroup(block.model, Constants.BLOCK_COLLISION_GROUP)
		for _, part in modelParts(block.model) do
			local was = saved[part]
			if was ~= nil then
				part.Transparency = was
			end
		end
	end)
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

-- The top of whatever stands in `x`'s column, or `floorY` if nothing does. This
-- is what the bolt actually hits — resolved at strike time, not when the warning
-- went up, so ten seconds of building under the marker counts.
--
-- `floorY` is a parameter rather than `baseTopY` because a PVP lane stands on its
-- own platform: the classic run measures from the arena base, a match measures
-- from the slab the lane is building on. The column test is what keeps this lane-
-- safe either way — a cell has to be within half a block of `x` to count, and
-- lanes are LANE_SPACING (120) apart.
local function highestAt(x: number, floorY: number): Vector3
	local best = floorY
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

-- One bolt, wherever it was aimed. Two things call this: the storm's own clock,
-- and a Lightning block resolving on settle.
--
-- Deliberately says nothing about the *warning*. The marker belongs to the storm's
-- state machine, which is the only thing that ever raises one, and it clears it
-- beside its own `pendingStrikeX = nil` — a Lightning block landing mid-warning
-- must not wipe the marker for a strike that is still coming.
--
-- `exclude` is spared the impulse, for the block that called the bolt down on
-- itself: it is about to be destroyed, and throwing it first only means the wreck
-- lands somewhere the player can't account for.
local function strikeLightning(origin: Vector3, exclude: Block?, source: Instance?)
	-- Who announces the bolt. The arena for a classic run, and the lane's own
	-- platform for a PVP match — six lanes can be struck in the same second, and
	-- one attribute on one folder can only ever describe one of them. Whoever owns
	-- the floor the bolt is aimed at is the thing that says it was.
	local announcer = source or workspace:FindFirstChild(Constants.ARENA_NAME)
	if announcer then
		-- Every client draws the bolt off this attribute. The server says only
		-- *where* it struck; attributes replicate, so the flash costs no packet
		-- of its own and a client that misses it simply doesn't draw one.
		announcer:SetAttribute(Constants.STRIKE_ATTRIBUTE, origin)
	end

	Sfx.playAtPosition("Lightning", origin, Constants.LIGHTNING_VOLUME)
	blastAt(
		origin,
		Constants.LIGHTNING_RADIUS,
		Constants.LIGHTNING_PRESSURE,
		Constants.LIGHTNING_IMPULSE,
		exclude
	)
end

-- Lightning blocks: the bolt comes down on the piece the moment it comes to rest.
--
-- No warning marker, because there was nothing to warn about until the player put
-- it there — the piece *is* the announcement, and it has been visible in their
-- hand for the whole turn. That's what separates this from the storm's version,
-- which has to warn precisely because nobody chose it.
--
-- The block goes with the strike, the way a Bomb does: it conducted the bolt, and
-- a piece left standing at the epicentre of its own strike reads as the effect
-- having missed.
--
-- Safe in PVP with no lane check of its own. LIGHTNING_RADIUS (26) against
-- LANE_SPACING (120) leaves the nearest neighbouring tower some 94 studs away,
-- well outside anything `blastAt` will touch — so nobody can call a bolt down on
-- somebody else's lane.
local function callLightning(block: Block)
	local origin = block.root.Position
	strikeLightning(origin, block)
	block.model:Destroy()
end

-- Drives the strikes while a Stormy zone is up: choose a spot, warn for ten
-- seconds, land the bolt, wait a randomised gap, repeat.
--
-- The gap is measured from the last strike and the warning sits *inside* it, so
-- raising the warning doesn't quietly slow the storm down.
local function updateLightning()
	-- Normally the Stormy zone's hazard; the Lightning Storm gamemode turns it
	-- on everywhere for the whole round.
	--
	-- Off during a PVP match, because the match runs its own storm: `PvpService`
	-- drives one clock for the whole board and strikes every lane on it, through
	-- `TowerService.strikeColumn` below. This driver is single-lane by
	-- construction — one warning column, standing on the classic run's floor,
	-- announced by one attribute on the arena — and pointing it at six towers
	-- would mean striking whichever one happened to be at its X.
	--
	-- The marker still has to be cleared here: a zone can turn stormy in the last
	-- seconds of a classic round, and the match that follows must not inherit a
	-- red column standing over a tower that no longer exists.
	if pvpActive then
		if pendingStrikeX ~= nil then
			pendingStrikeX = nil
			local folder = workspace:FindFirstChild(Constants.ARENA_NAME)
			if folder then
				folder:SetAttribute(Constants.WARN_ATTRIBUTE, nil)
			end
		end
		return
	end

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
		-- Marker off first, bolt second. A client that saw both attributes change
		-- in the same frame should be left with a flash and no marker, never the
		-- other way round.
		local arena = workspace:FindFirstChild(Constants.ARENA_NAME)
		if arena then
			arena:SetAttribute(Constants.WARN_ATTRIBUTE, nil)
		end
		strikeLightning(highestAt(pendingX, baseTopY))
		return
	end

	-- Nothing pending: start the next warning once the gap has run down, minus
	-- the warning it has to fit in.
	if now >= nextStrikeAt - Constants.LIGHTNING_WARNING_SECONDS then
		chooseStrike()
	end
end

local function paint(block: Block, color: Color3)
	-- The cells, which is everything the server has; each client's rounded body
	-- reads its colour off them, so a bomb's red flash reaches the screen through
	-- the same write.
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
			playAtBlock("BombBeep", block.root)
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
--
-- `fire` is the chain this block is joining, passed along by `spreadBurn`. A
-- block lit without one starts its own — that's the piece that arrived alight,
-- and it's what hands the chain its budget. Two Burning pieces in the same tower
-- are two fires with a budget each, which is right: they're two hazards.
local function igniteBlock(block: Block, fire: BurnFire?)
	-- A Noob would char and disintegrate like scenery, which reads as a bug
	-- rather than a joke.
	if block.burnStartedAt ~= nil or block.custom or block.root.Parent == nil then
		return
	end
	block.burnStartedAt = os.clock()
	block.fire = fire or { spreadsLeft = Constants.BURN_MAX_SPREAD }

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
		local kind = if block.blockType then block.blockType.kind else nil

		-- A Sacrifice takes the block it *hits*, and it's the only type that cares
		-- what that was. It's tested before the impact-speed gate below on purpose:
		-- this is the one piece in the game that is aimed at a particular block, and
		-- "you hit the block you were aiming at, but too gently for it to count"
		-- would be an outcome nobody can see the rule behind. Hitting the base, a
		-- platform or a neighbour's wall isn't in `blockByModel` and is safe by
		-- construction, and leaves the piece still armed for the block it was
		-- actually aimed at.
		if kind == "sacrifice" and not block.resolved then
			local victim = blockOf(hit)
			if victim ~= nil and victim ~= block then
				block.resolved = true
				sacrificeBlock(block, victim)
			end
		end

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

		-- Bombs resolve on impact too, but on a *hard* one: a bomb that lands
		-- gently hasn't armed, and gets to settle instead. Glue and Clone wait for
		-- the block to come to rest, which the height poll handles.
		if block.resolved or kind ~= "explosion" then
			return
		end
		block.resolved = true
		armBomb(block)
	end

	for _, part in modelParts(block.model) do
		part.Touched:Connect(onTouched)
	end
end

-- Speed lines: one narrow Trail per cell, hung on an Anvil for the fall.
--
-- A Trail is the right instrument and needs no gate of its own — it draws only
-- while its attachments are *moving*, so the lines appear when the block is
-- released, stretch out as it accelerates to `FALL_SPEED`, and are gone a fifth
-- of a second after it lands. Nothing has to decide when a block counts as
-- falling, and nothing has to clean up.
--
-- Per cell rather than per block, because that's what makes them read as *lines*:
-- a single ribbon the width of a four-cell I-piece is a smear, four narrow ones
-- following the cells are speed.
--
-- Attached here rather than at build time on purpose. A held piece is steered
-- left and right for a whole turn before it's dropped, and a trail on that would
-- draw speed lines across the sky while the player is still deciding.
local function attachSpeedLines(model: Model)
	local half = Constants.ANVIL_LINE_WIDTH / 2
	for _, part in modelParts(model) do
		local left = Instance.new("Attachment")
		left.Name = "SpeedLineA"
		left.Position = Vector3.new(-half, 0, 0)
		left.Parent = part

		local right = Instance.new("Attachment")
		right.Name = "SpeedLineB"
		right.Position = Vector3.new(half, 0, 0)
		right.Parent = part

		local trail = Instance.new("Trail")
		trail.Name = "SpeedLines"
		trail.Attachment0 = left
		trail.Attachment1 = right
		trail.Color = ColorSequence.new(Constants.ANVIL_LINE_COLOR)
		trail.Transparency = Constants.ANVIL_LINE_TRANSPARENCY
		trail.Lifetime = Constants.ANVIL_LINE_SECONDS
		trail.LightEmission = 1
		-- Faces the camera rather than lying in the world plane: the shot is a
		-- fixed side-on one, and a ribbon edge-on to it would be invisible for the
		-- exact frames it exists to sell.
		trail.FaceCamera = true
		trail.Parent = part
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
	pack: SkinPacks.SkinPack?,
	laneX: number
): Block
	local block: Block = {
		model = model,
		root = root,
		laneX = laneX,
		settled = false,
		slowSince = nil,
		settledOnce = false,
		shape = shape,
		skin = skin,
		pack = pack,
		blockType = blockType,
		baseColor = baseColor,
		custom = custom,
		-- Resolved rather than read straight off the skin: Duck's quack is a Sound
		-- a human put in the place, so its id only exists there. Everything else
		-- writes its id in BlockSkins and comes back unchanged.
		impactSound = attachSound(root, "Impact", BlockSkins.impactIdFor(skin), skin.volume),
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
	-- Again here, because this is the one funnel *every* block goes through and a
	-- Noob rig arrives as a ready-made model that never saw `buildPiece`. Same
	-- value either way, so the double write is idempotent.
	model:SetAttribute(Constants.SKIN_ATTRIBUTE, skin.id)
	-- Everything in the tower shares one group, so a Ghost has a single thing to
	-- ignore. Ghosts are moved out of it by `startGhost` and back into it when
	-- they solidify.
	setCollisionGroup(model, Constants.BLOCK_COLLISION_GROUP)
	watchLanding(block)

	-- A Burning block arrives already alight; everything else has to catch.
	if blockType and blockType.kind == "burning" then
		igniteBlock(block)
	end
	-- An Anvil draws speed lines for the fall it's about to make. Here rather than
	-- in `buildPiece`, so the trails start at the drop and not while the piece is
	-- still being steered around the sky.
	if blockType and blockType.kind == "anvil" then
		attachSpeedLines(model)
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

	-- The copy inherits the original's pack *and its colour*, because otherwise it
	-- isn't a copy. `buildPiece` rolls a fresh hue per block, so a Clone used to
	-- hand back a piece in an unrelated colour — the one type in the game whose
	-- whole promise is that the thing it makes looks like the thing it came from,
	-- and the only one that visibly broke it. It went unnoticed for players wearing
	-- a colour pack, where `SkinPacks.colorFor` returns the same shade for both and
	-- the copy matched by accident.
	--
	-- `baseColor`, not whatever the cells are wearing now: a charring Burning block
	-- or a Bomb mid-flash is repainted, and a copy should be of the block, not of
	-- the state it happens to be in.
	local model, root, color = buildPiece(shape, block.skin, nil, block.pack, block.baseColor)
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
	-- The copy belongs to whatever lane its original does. A Clone that landed in
	-- the wrong lane's books would be measured as somebody else's height.
	registerBlock(model, root, shape, block.skin, nil, color, false, block.pack, block.laneX)
end

-- Burning spreads by contact, checked from the poll rather than from Touched:
-- a block already resting against its neighbour never fires Touched again, and
-- resting against something is exactly the case that should catch.
--
-- The chain's budget is spent here and nowhere else, one block per ignition, so
-- it doesn't matter whether the fire spreads as a line or a fan — three blocks
-- is three blocks either way. A block that's already alight isn't charged for:
-- `igniteBlock` refuses it, and paying for a neighbour a *different* arm of the
-- same fire already took would end the fire early for no visible reason.
local function spreadBurn(block: Block)
	local fire = block.fire
	if fire == nil or fire.spreadsLeft <= 0 then
		return
	end

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { block.model }

	for _, part in modelParts(block.model) do
		local reach = part.Size + Vector3.one * Constants.BURN_SPREAD_RADIUS
		for _, other in workspace:GetPartBoundsInBox(part.CFrame, reach, params) do
			if fire.spreadsLeft <= 0 then
				return
			end
			local model = other:FindFirstAncestorOfClass("Model")
			local neighbour = if model then blockByModel[model] else nil
			-- Checked before igniting rather than after, because `igniteBlock`
			-- is silent about whether it did anything and an already-burning
			-- neighbour must not cost the fire a block it never took. These are
			-- the same three refusals it makes, which is the coupling to watch:
			-- a new one there needs one here, or the budget pays for nothing.
			if
				neighbour ~= nil
				and neighbour.burnStartedAt == nil
				and not neighbour.custom
				and neighbour.root.Parent ~= nil
			then
				fire.spreadsLeft -= 1
				igniteBlock(neighbour, fire)
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

-- Hand one player's piece to physics.
--
-- The shared half of a drop: everything that is true of a block entering the
-- world whichever mode dealt it. Called by the holder's own Release, by the
-- classic turn loop when the clock runs out or the holder leaves, and by each
-- PVP lane's own clock — hence no ownership check, the caller has already
-- decided this piece is being let go.
--
-- Returns the block it became, or nil if that player wasn't holding one.
function TowerService.dropPiece(player: Player): Block?
	local piece = heldBy[player]
	if piece == nil then
		return nil
	end
	heldBy[player] = nil

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

	local dropped = registerBlock(
		piece.model,
		piece.root,
		piece.shape,
		piece.skin,
		piece.blockType,
		piece.baseColor,
		piece.custom,
		piece.pack,
		piece.laneX
	)

	-- Starts the moment it's let go, not when it lands — phasing is the fall.
	-- After `registerBlock`, which is what put it in the ordinary block group.
	if piece.blockType ~= nil and piece.blockType.kind == "ghost" then
		startGhost(dropped)
	end
	-- Everyone hears the drop from where it happened. The holder also gets their
	-- own confirmation cue locally (Drop2, played client-side).
	playAtBlock("Drop", piece.root)
	placerOf[piece.model] = piece.player
	TowerStatsService.recordBlockPlaced(piece.player)

	return dropped
end

-- The classic turn ends. `dropPiece` does the block half; this is the half that
-- only means anything with a turn queue behind it — who gets paid for the height
-- it gains, the turn funnel, and the state the HUD draws between turns.
function TowerService.release()
	local player = turnHolder
	if player == nil or TowerService.dropPiece(player) == nil then
		return
	end
	turnHolder = nil

	lastDropper = player

	AnalyticsService.step(player, "turn", "Dropped")
	-- Only the first placement of the round advances the round funnel; `step`
	-- dedupes the rest against the session, so this is called on every drop and
	-- counted once.
	AnalyticsService.step(player, "round", "First Piece Placed")
	AnalyticsService.onboarding(player, 3)

	state.phase = PHASE.SETTLING
	state.holderUserId = 0
	state.turnEndsAt = 0
	state.shapeId = 0
	state.blockTypeId = 0
	state.pieceTop = 0
	broadcast()
end

-- Build a piece and hand it to `player` to aim over lane `laneX`, which stands on
-- `floorY`.
--
-- The shared half of starting a turn: roll the shape, the skin and the hazard,
-- build the model, dress it for the zone, park it clear of whatever is already
-- standing in that lane, and mark it as theirs. Everything a *turn* means — the
-- clock, the queue, the funnel, the HUD state — belongs to the caller, because
-- the two modes disagree about all of it.
--
-- `chance` replaces the odds this one piece is special, for a caller whose rate
-- isn't a property of the stage. PVP's is a ramp on its own match clock, and that
-- clock lives in PvpService — passing the number per piece keeps it there rather
-- than teaching this file a second mode's sense of time. nil takes the stage's,
-- which is every classic turn. The `blockrate` console knob still outranks both.
--
-- Returns the piece, so a caller that runs its own clock has something to read
-- the spawn altitude off without going back through the table.
function TowerService.dealPiece(player: Player, laneX: number, floorY: number, chance: number?): Held
	local shape: Shapes.Shape? = nextShape
	nextShape = Shapes.random()

	-- Rolled per piece. Skin is pure flavour; type is the hazard, and it gets
	-- likelier the more floors the run has cleared — or, where the caller passed
	-- its own `chance`, at whatever rate that caller is running. Either can be
	-- pinned for exactly this one piece by the "block" cmdr command.
	local commanded = skinForced
	local skin = if commanded then forcedSkin :: BlockSkins.Skin else BlockSkins.random()
	local blockType = if blockTypeForced
		then forcedBlockType
		else BlockTypes.roll(
			state.checkpoints,
			stage.blockTypeScale,
			devBlockTypeChance or chance or stage.blockTypeChance
		)
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
	local pivot = spawnPivot(laneX, floorY, halfHeight)
	piece:PivotTo(pivot)
	-- Nothing the holder is still aiming may touch the tower.
	local collision = suspendCollision(piece)
	-- Tells the holder's client "this one is yours" so it can hide the real piece
	-- and drive a local preview instead. In PVP every lane has one of these up at
	-- once, and each client still finds exactly its own — the attribute has always
	-- been keyed by user id, so nothing about that lookup had to change.
	piece:SetAttribute(Constants.HELD_ATTRIBUTE, player.UserId)
	piece.Parent = arena

	local dealt: Held = {
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
		laneX = laneX,
		floorY = floorY,
	}
	heldBy[player] = dealt
	return dealt
end

local function beginTurn(player: Player)
	local dealt = TowerService.dealPiece(player, CLASSIC_LANE, baseTopY)
	local shape = dealt.shape
	local blockType = dealt.blockType
	local pack = dealt.pack

	turnHolder = player
	state.phase = PHASE.AIMING
	state.pieceTop = pieceTopOf(dealt)
	state.holderUserId = player.UserId

	-- The turn opens short and is extended to the full clock by the first steer
	-- or rotate (see `aim`). A player's first turns get the whole thing up front
	-- — they're reading the controls hint — and a gamemode with turns already
	-- shorter than the idle window keeps its own, so the fast mode isn't handed
	-- a longer turn than it asked for.
	turnsDealt[player] = (turnsDealt[player] or 0) + 1
	heldTouched = turnsDealt[player] <= Constants.IDLE_GRACE_TURNS
	turnStartedAt = workspace:GetServerTimeNow()
	local window = if heldTouched
		then stage.turnSeconds
		else math.min(Constants.IDLE_TURN_SECONDS, stage.turnSeconds)
	state.turnEndsAt = turnStartedAt + window
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
			-- Terminal velocity. *Every* block has one now — `Constants.FALL_SPEED`
			-- — because a tower that gets hit with the full energy of an unclamped
			-- fall scatters however carefully the piece was aimed. A Feather's is
			-- far lower and is the entire type rather than a safety net.
			--
			-- Only the downward half is capped, so a blast can still throw a block
			-- as hard as it likes; and only while it's moving, so a settled block is
			-- never written to.
			--
			-- Folded into the Z clamp's write rather than done separately: one
			-- AssemblyLinearVelocity assignment per block per frame, same as before.
			local limit = if block.blockType ~= nil and block.blockType.kind == "feather"
				then Constants.FEATHER_FALL_SPEED
				else Constants.FALL_SPEED
			local fall = math.max(velocity.Y, -limit)
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

-- Live blocks, thrown clear rather than deleted — the caller destroys them once
-- the wreck has been seen.
--
-- `cutoffY` limits the sweep to blocks whose highest point is at or below a line;
-- **nil takes every block there is**, which is what a checkpoint wants. The
-- checkpoint used to pass the new floor's underside, and the consequence was that
-- the tower's top layer — the blocks inside the slab band, plus anything still
-- falling above it — survived into the next stage and stuck out around the new
-- floor. A cleared stage is a clean floor now: nothing carries over.
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

local function blastBlocks(cutoffY: number?): { Block }
	local debris = {}
	for index = #blocks, 1, -1 do
		if cutoffY ~= nil and highestPointOf(blocks[index]) > cutoffY then
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
-- `blastBlocks` empties its list first: that list feeds `restingTopY`, and
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

-- Dress one slab of a new floor and play it in.
--
-- Enters as a sliver at its own centre line and stretches outward to full width;
-- because the slab is anchored, tweening Size grows it evenly about its position
-- rather than dragging one face. Per slab rather than per floor, so a Split floor
-- opens as two slivers spreading apart and the gap is the last thing you see
-- appear — which is exactly the thing the player needs to notice.
local function playInSlab(part: BasePart)
	local full = part.Size

	part.Material = Enum.Material.Neon
	part.Color = Constants.PLATFORM_SPAWN_COLOR
	-- A floor, and the same floor as the base — a checkpoint is another storey of
	-- the same building, so it can't be a different surface to land on.
	part.CustomPhysicalProperties = Constants.FLOOR_PHYSICS
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = Vector3.new(0.5, full.Y, full.Z)

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

-- The new floor, standing at `topY`. Returns its slabs — more than one whenever
-- the layout that won has more than one, which is the whole point of layouts.
--
-- Numbered by the floor it is, not by how many are currently standing — previous
-- ones are demolished, so `#platforms` would name every floor after the first
-- "Checkpoint2". `state.checkpoints` is still the count *behind* this one at
-- spawn time; it's incremented once the demolition finishes, which also makes it
-- the right number to ask `PlatformLayouts.pick` with.
local function spawnCheckpoint(topY: number): { BasePart }
	local floor = state.checkpoints + 1
	local layout = PlatformLayouts.pick("checkpoint", floor)

	local slabs
	if layout then
		slabs = PlatformLayouts.build(layout, topY, arena, `Checkpoint{floor}`)
	else
		local full = Constants.PLATFORM_SIZE
		local part = Instance.new("Part")
		part.Name = `Checkpoint{floor}`
		part.Anchored = true
		part.Size = full
		part.Position = Vector3.new(0, topY + full.Y / 2, Constants.PLANE_Z)
		part.Parent = arena
		slabs = { part }
	end

	for _, slab in slabs do
		table.insert(platforms, slab)
		playInSlab(slab)
	end
	return slabs
end

-- The storm arrives. Everything the players built gets blown off the plane and
-- the run starts over from the base — no checkpoints, first target, fresh clock.
--
-- The debris is left to fly for a moment before cleanup rather than blinking
-- out, because the tower coming apart is the whole point of the deadline. It all
-- goes one way — left — and the white-out waits for it: `STORM_FADE_DELAY_SECONDS`
-- is set to about the time the wreck needs to clear the frame, so the order the
-- players see is the tower leaving and *then* the screen going.
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
		-- All of it to the **left**, as one gust. A random scatter read as an
		-- explosion going off under the tower — which is what a Bomb and a
		-- checkpoint demolition already look like — and left the wreck milling
		-- about in frame. A storm is weather: it comes from a direction, it takes
		-- the tower with it, and the shot ends on an empty arena rather than on a
		-- cloud of debris.
		--
		-- Jittered per block so the tower comes apart on the way out instead of
		-- sliding off as one sheet, and given a little depth so the wreck stops
		-- being a flat cut-out the moment it leaves the play plane.
		local shove = Vector3.new(
			-Constants.STORM_BLAST_HORIZONTAL - math.random() * Constants.STORM_BLAST_HORIZONTAL_JITTER,
			Constants.STORM_BLAST_UP * (0.6 + math.random() * 0.8),
			(math.random() * 2 - 1) * Constants.STORM_BLAST_DEPTH
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
	-- A fresh run shouldn't inherit the last one's weather — or its gravity.
	restoreDefaultZone()
	-- A run starts un-voted; last run's gamemode doesn't carry over. The round
	-- break overwrites this with whatever the players then vote for — this is the
	-- baseline for the paths that reset without a vote (server start).
	applyStage(Gamemodes.DEFAULT)
	-- After the checkpoint count is zeroed above, so the clock comes back to the
	-- first stage's length rather than keeping the last run's growth.
	restartStormClock()
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
	local player = turnHolder
	local piece = if player ~= nil then heldBy[player] else nil
	if player == nil or piece == nil then
		return
	end
	heldBy[player] = nil
	turnHolder = nil
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

		local newFloor = spawnCheckpoint(baseTopY + height)
		task.wait(Constants.PLATFORM_GROW_SECONDS)

		-- The tower below is scaffolding now: the floor is the new ground, and
		-- keeping a few hundred settled parts alive under it buys nothing but
		-- physics cost. Height is measured off the floor's own top, so the
		-- readout doesn't move when they go.
		--
		-- Measured from the *lowest* slab in the new floor rather than from a
		-- fixed PLATFORM_SIZE thickness below its scoreline. A layout may hang
		-- slabs below the scoreline — Pedestal's wings sit eight studs down — and
		-- a cutoff drawn at the scoreline would have the new floor demolish its
		-- own wings the instant it landed.
		local cutoff = math.huge
		for _, slab in newFloor do
			cutoff = math.min(cutoff, slab.Position.Y - slab.Size.Y / 2)
		end
		-- Every block, not just the ones under the new floor. The floor lands on
		-- the tower's highest point, so a cutoff at its underside spared whatever
		-- was inside the slab band — the last layer the players placed — and left
		-- it poking out around the new ground for the rest of the run. It also
		-- spared anything still in the air. A cleared stage starts on a bare floor.
		--
		-- The platforms below still go by the cutoff: the new floor's own slabs are
		-- in that list, and they're the one thing that has to survive.
		local debris = blastBlocks(nil)
		-- The floors the run has already climbed past go with it. The new floor's
		-- slabs were pushed onto `platforms` a moment ago and every one of their
		-- tops sits above the cutoff, so they aren't caught by their own
		-- demolition.
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
		--
		-- Unless the round took the cadence out: Wild Weather has no calm floors
		-- to count towards the next twist, so every checkpoint rolls a special
		-- straight away.
		local zone = if stage.specialsOnly
			then Zones.rollSpecial(state.zoneId)
			else Zones.next(state.checkpoints, state.zoneId)
		state.zoneId = zone.id
		state.zoneSky = math.random(1, 255)
		applyZoneToTower()
		CashService.awardZone()
		-- Paired with the payout on purpose: the quest line promises this floor is
		-- worth something, so the moment the promise is kept is the moment it stops
		-- being shown. Hands the rare skin to anyone on their first checkpoint and
		-- closes the quest for the rest — see CheckpointQuestService.
		CheckpointQuestService.award()
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
		-- And a little more time to climb it: `state.checkpoints` went up above,
		-- so this stage's clock is one STORM_TIME_GROWTH longer than the last.
		restartStormClock()
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

-- Set how long is left on the stage clock, in seconds from now. Used by the
-- "setstorm" cmdr command.
--
-- The deliberate opposite of `extendStorm`: that one *adds* to the deadline
-- because a purchase has to stack honestly, and this one *replaces* it because
-- the whole point of a dev handle is to land on a number without doing the
-- arithmetic from wherever the clock happens to be. Nothing but the console
-- should call it — the products go through `extendStorm`.
--
-- `stormSeconds` is raised to match when the new time is longer than the stage
-- was. It's the denominator the HUD draws the storm bar against, so leaving it
-- alone would hand the bar a fraction over 1 and draw it past its own end. Never
-- lowered: a shorter time left is exactly what a partly-drained bar looks like,
-- and shrinking the whole stage to match would make the bar jump back to full.
--
-- Zero is allowed and means "now" — the poll fires the storm on its next tick,
-- which is the only way to reach the wreck without waiting out a stage. Refused
-- during a checkpoint or a round break for the same reason `extendStorm` is:
-- both sequences set `stormEndsAt` themselves when they end, so a time written
-- inside one is a time thrown away.
function TowerService.setStorm(seconds: number): boolean
	if checkpointActive or intermission then
		return false
	end
	if seconds < 0 then
		return false
	end

	state.stormEndsAt = workspace:GetServerTimeNow() + seconds
	state.stormSeconds = math.max(state.stormSeconds, seconds)
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

-- Hold the odds a piece is special at a flat number, for as long as it's set.
-- Used by the "blockrate" cmdr command; nil hands the roll back to the curve.
--
-- This exists because the curve is a function of `checkpoints`, which resets to
-- zero every time a play test restarts — so at BASE_CHANCE a dev session sees
-- one special piece in thirty-three, and testing anything about them means
-- clearing stages first. It rides the same `override` argument Roulette uses, so
-- it bypasses the cap as well as the curve and the number asked for is the
-- number that happens.
--
-- Deliberately *not* persisted and not exposed to players: it's a console knob,
-- and a fresh server comes up on the real curve.
function TowerService.setBlockTypeChance(chance: number?)
	devBlockTypeChance = chance
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

-- A mode to play next instead of asking. Set by the `gamemode` cmdr command and
-- consumed by the first `nextMode` after it, so it forces exactly one round —
-- otherwise a dev pin would quietly become the server's permanent ballot.
local forcedMode: string? = nil

-- What the next round plays as: the pin if one is set, otherwise the poll.
--
-- **Yields** in the second case, for the length of the vote. An unregistered or
-- skipped vote comes back nil, and `modifierFor` turns that into the Classic
-- numbers — the same round winning the Classic panel would have produced.
local function nextMode(): string?
	local pinned = forcedMode
	if pinned ~= nil then
		forcedMode = nil
		return pinned
	end
	return GamemodeVoteService.startVote()
end

-- Put the ballot up and hand the players the rounds they pick, until one of those
-- rounds is a classic one this function can hand back to.
--
-- **Yields** for the length of the vote, and again for a whole match every time
-- PVP wins. PVP isn't a set of numbers for the round that follows — it *is* the
-- round: the board goes to PvpService and comes back empty, and then the players
-- vote again rather than being dropped into a classic run nobody picked. Voting
-- PVP twice running plays two matches, which is the honest reading of the ballot.
--
-- Callers keep whatever happens *once* per round — the wreck, the reset, the
-- fresh clock, the round funnel — outside this. That's what makes PVP a peer of
-- the other modes rather than an interlude, and it's why the opening vote and the
-- round break can share one implementation despite agreeing on nothing else.
-- The zone a round opens in, once its rules are known.
--
-- Normally there's nothing to do: `resetRun` has already put the world back to
-- Clear Skies, which is where a run should start. A specials-only round has no
-- clear skies to start in — and starting in them anyway would leave the *first*
-- stage, the longest one and the one before any checkpoint has been cleared,
-- playing exactly like Classic while the ballot card promised otherwise.
--
-- Rolled against the zone that's up, so the mode doesn't open on the weather the
-- last round ended in.
local function applyOpeningZone()
	if not stage.specialsOnly then
		return
	end
	local zone = Zones.rollSpecial(state.zoneId)
	state.zoneId = zone.id
	state.zoneSky = math.random(1, 255)
	-- Dresses the (empty) board and writes `workspace.Gravity`, so a round opening
	-- in Space opens in Space's gravity rather than picking it up at the first
	-- checkpoint.
	applyZoneToTower()
end

local function settleOnAMode()
	applyStage(Gamemodes.modifierFor(nextMode()))

	while stage.pvp do
		pvpActive = true
		-- The base is the classic game's floor and PVP has six of its own; off it
		-- goes for the length of the match. Paired with the flag rather than done
		-- inside `runMatch` because the base is this file's, and because the pcall
		-- below then guarantees it comes back even if the match throws.
		setBaseOnBoard(false)
		local ok, err = pcall(pvp().runMatch)
		setBaseOnBoard(true)
		-- A match rolls its own zones through `applyZone`, which makes them true in
		-- the world rather than only on the PVP packet. Put the weather back before
		-- the ballot reopens: the vote is played out under clear skies, and a
		-- classic round following a match used to open in whatever zone that match
		-- happened to end in — Retro studs and all. Out here with the base rather
		-- than inside `runMatch` for the same reason the base is: the zone is this
		-- file's, and a match that throws still has to give it back.
		restoreDefaultZone()
		pvpActive = false
		-- A match that throws must not take the server's rounds with it. The board
		-- is left to `runMatch`'s own cleanup; what matters here is that control
		-- reaches the vote again rather than dying inside a `while` with the game
		-- parked behind it.
		if not ok then
			warn(`[TowerGame] PVP match ended in error: {err}`)
		end
		applyStage(Gamemodes.modifierFor(nextMode()))
	end

	-- The round's rules are known now, and one of them can be "there is no calm
	-- zone". After the loop, so a PVP match that came first isn't handed weather
	-- picked for the classic round waiting behind it.
	applyOpeningZone()
end

-- The game opens on a ballot rather than on a round nobody picked.
--
-- Before this, a server's first round was always the un-voted Classic numbers —
-- the one round of the session the players had no say in, and the round most of
-- them spend their first minutes in. Everything after it was voted; the first one
-- being the exception was an accident of the vote living only in the round break.
--
-- It waits for somebody to be in the queue. A poll opened against an empty server
-- is fifteen seconds of nothing followed by the default, which is the exact round
-- this exists to stop handing out — and the first player through the door should
-- arrive to a ballot rather than to the tail of one that ran without them.
--
-- No wreck, no reset, no `reportRoundLost`: there is no round behind this one.
-- `intermission` is set for the same reason the round break sets it — the turn
-- queue parks, the storm clock is ignored, placements are refused — so the vote
-- isn't a screen over a game already running underneath it.
local function runOpeningVote()
	intermission = true

	task.spawn(function()
		while #queue == 0 do
			task.wait(Constants.POLL_INTERVAL)
		end
		-- A beat for the arriving client to finish mounting its UI, so the ballot
		-- doesn't open behind a loading screen and lose seconds off its own clock.
		task.wait(Constants.OPENING_VOTE_DELAY)

		settleOnAMode()

		-- The round's clock starts once its rules are known, so the players don't
		-- lose any of it to the vote they were made to sit through.
		restartStormClock()
		state.phase = PHASE.SETTLING
		broadcast()
		reportRoundStarted()

		intermission = false
	end)
end

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

		-- The vote, plus however many PVP matches the players vote themselves into
		-- before landing on a classic round. Shared with the opening vote.
		settleOnAMode()

		-- The new round's clock starts once the rules are known, so the players
		-- don't lose any of it to the vote they were made to sit through.
		restartStormClock()
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
-- End the round now and play `modeId` next, skipping the vote.
--
-- The dev handle on everything that only happens between rounds. It exists
-- because PVP is otherwise a full storm clock away — five minutes of classic
-- play, and then a poll that four other people get a say in — which is a very
-- long way to go to look at a lane. It routes through the real round break, so
-- what it produces is the round the vote would have produced.
--
-- Refuses mid-checkpoint and mid-break for the same reason the action products
-- do: those sequences set the state this would be writing over.
function TowerService.forceRound(modeId: string): boolean
	if checkpointActive or intermission then
		return false
	end
	forcedMode = modeId
	runRoundBreak()
	return true
end

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
	state.height = restingTopY(CLASSIC_LANE, baseTopY) - baseTopY
	broadcast()
	return true
end

-- Returns true when the stage changed and clients need to hear about it.
local function updateStorm(height: number): boolean
	local now = workspace:GetServerTimeNow()

	-- Nothing here runs during a checkpoint or a round break: `updateHeight`
	-- returns before it gets this far, and holds the storm clock on its way out.
	-- `runRoundBreak` then sets `stormEndsAt` fresh once the new round's rules are
	-- known, so no part of the round is spent on the poll either.

	-- Nobody playing: hold the clock rather than letting it expire against an
	-- empty server.
	if #queue == 0 then
		holdStormClock()
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

-- Turn a block to stone.
--
-- The visible half of anchoring. Being permanently anchored makes a block part of
-- the scenery rather than part of the tower, and it should look like it: the skin
-- it rolled stops mattering the moment it can never move again, and a piece that
-- is quietly immovable is the sort of thing a player only discovers by building
-- against it.
--
-- Colour *and* material, because each carries half of it — grey alone reads as a
-- grey block, Slate alone as a textured one — and because the client's rounded
-- body mirrors exactly those two properties off the cell (see TowerBodyController),
-- so this is also what makes the shell a player actually sees turn to stone.
--
-- The attribute is what makes it stick: `applyZoneLook` re-dresses every standing
-- block on a zone change, and without a carve-out the next zone would hand the
-- statue its skin back.
local function petrify(model: Model)
	model:SetAttribute(Constants.STATUE_ATTRIBUTE, true)
	for _, part in modelParts(model) do
		part.Color = Constants.STATUE_COLOR
		part.Material = Constants.STATUE_MATERIAL
		-- A tiled skin pattern is a decal on top of the material, so it would
		-- survive the change and leave a duck-print statue.
		for _, texture in part:GetChildren() do
			if texture:IsA("Texture") then
				texture.Transparency = 1
			end
		end
	end
end

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
	petrify(block.model)
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
	elseif kind == "magnet" then
		magnetiseBlock(block)
	elseif kind == "sacrifice" then
		-- Only reachable through a Mystery reveal, and with no victim to hand it:
		-- a piece that turns out to be a Sacrifice has already landed, so the
		-- impact it would have read is gone and what it's resting on is the honest
		-- answer. A block *dealt* as a Sacrifice never arrives here — it resolves
		-- against whatever it hit, on contact.
		sacrificeBlock(block)
	elseif kind == "lightning" then
		callLightning(block)
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
-- Two are deliberately absent because they resolve on *impact* instead (see
-- `watchLanding`): **Bomb**, where one that reaches settle without arming is one
-- that landed too gently to trigger it, and **Sacrifice**, which takes the block
-- it hit — the piece is aimed at something, so what it ran into is the answer and
-- what it later comes to rest against is not. Burning is absent for a third
-- reason: it arrives already alight, lit in `registerBlock`. The physics types
-- (Bouncy, Anvil, Ice, Feather) have nothing to resolve at all: their whole
-- effect is the PhysicalProperties they were built with.
local SETTLE_RESOLVED: { [string]: boolean } = {
	glue = true,
	clone = true,
	anchor = true,
	crate = true,
	mystery = true,
	magnet = true,
	-- Lightning waits for the settle for Glue's reason: the bolt comes down on
	-- where the piece *ended up*, not where it first touched something.
	--
	-- Missing from this table is what made a dealt Lightning block do nothing at
	-- all. `applySettleEffect` has had its branch since the type was added, and
	-- that path is reached two ways — a Mystery reveal calls it directly (so a
	-- revealed Lightning always worked), and this table is the gate for everything
	-- else. A type with an effect and no entry here is a piece that lands, keeps
	-- its name plate, and is an ordinary block.
	lightning = true,
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

-- Everything the blocks themselves need doing every poll, whichever mode is
-- running: sweep the destroyed and the fallen, char what's burning, and decide
-- what has come to rest.
--
-- Split out of the height measurement below because those two used to be one
-- loop and only one of them belongs to the classic game. A PVP round has no
-- shared tower to measure and no storm to measure it against, but its blocks
-- still have to settle, still catch fire and still fall off the side — so this
-- half keeps running for the whole match while the half below is parked.
--
-- `floorY` is what "fallen off" is measured against. Every lane stands at the
-- same altitude, so one number covers the board.
local function sweepBlocks(now: number, floorY: number)
	for index = #blocks, 1, -1 do
		local block = blocks[index]
		if block.root.Parent == nil then
			removeBlockAt(index)
			continue
		end
		-- Knocked off the platform: stop paying for its physics.
		if block.root.Position.Y < floorY - Constants.DESPAWN_BELOW then
			removeBlockAt(index).model:Destroy()
			continue
		end
		-- Burning blocks char, spread, and eventually aren't there any more.
		if tickBurn(block, now) then
			removeBlockAt(index)
			continue
		end

		updateSettle(block, now)
	end
end

-- The scoring number for one lane: the top of everything settled in it, as studs
-- above the floor it stands on.
--
-- Deliberately narrower than `restingTopY`, which answers "what could a piece
-- land on". This one counts only blocks that have held still for
-- SETTLE_CONFIRM_SECONDS and skips Noobs entirely, because a walking block would
-- make the readout bob. Both exclusions are right for a score and wrong for
-- clearance, which is why the two measurements stayed separate.
local function measureLane(laneX: number, floorY: number): number
	local top = floorY
	for _, block in blocks do
		if block.laneX ~= laneX or block.root.Parent == nil then
			continue
		end
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
	-- They only exist in the classic lane; see `restingTopY`.
	if laneX == CLASSIC_LANE then
		for _, platform in platforms do
			local platformTop = partTopY(platform)
			if platformTop > top then
				top = platformTop
			end
		end
	end
	return top - floorY
end

local function updateHeight()
	local now = os.clock()

	-- A PVP round runs *inside* the classic round break, so `intermission` is up
	-- for the whole of it and the branch below would park the block sweep along
	-- with everything else. The sweep has to keep running: those blocks are the
	-- match. Everything past this point is the classic game's — one shared tower,
	-- a storm clock, a stage to clear — and none of it exists during a match.
	if pvpActive then
		sweepBlocks(now, baseTopY)
		-- The classic storm isn't running, and its bar has to say so for the whole
		-- match rather than only once the match is over: three minutes is long
		-- enough for a stale deadline to run out on screen, and the vote that
		-- follows is where the players were reading it.
		holdStormClock()
		return
	end

	-- The checkpoint cutscene and the round break each own the world while they
	-- run. Measuring a tower that's mid-demolition would spike the readout off
	-- flying debris and could clear the next stage from the wreckage of the last.
	if checkpointActive or intermission then
		-- Neither sequence lets the storm fire, so neither may let its bar drain.
		-- Both set the clock fresh when they end, so this is only ever what the
		-- players are looking at in the meantime — the wreck, the ballot, and any
		-- PVP matches voted in before a classic round is settled on.
		holdStormClock()
		if os.clock() - lastBroadcast > 1 then
			broadcast()
		end
		return
	end

	sweepBlocks(now, baseTopY)

	local height = measureLane(CLASSIC_LANE, baseTopY)
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
		-- A PVP match runs inside that break, so this covers it too — its lanes
		-- deal their own pieces and the queue has nothing to say about them.
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

		-- Ends on any of: the player released it (held goes nil), the clock
		-- expired, the holder left mid-turn, or a checkpoint took the piece away.
		-- The clock is re-read each pass rather than captured, because the first
		-- touch extends it (see `aim`) — a captured deadline would end the turn
		-- of the player who just woke up.
		while
			classicHeld() ~= nil
			and workspace:GetServerTimeNow() < state.turnEndsAt
			and player.Parent == Players
		do
			task.wait(0.1)
		end
		-- Read before the drop below, because that's what clears it: the piece
		-- still being here means the clock beat the player to it, while it going
		-- nil is them having released it themselves.
		local autoDropped = classicHeld() ~= nil
		if autoDropped then
			TowerService.release()
		end

		noteTurnIdleness(player, autoDropped)

		task.wait(Constants.SETTLE_SECONDS)
	end
end

-- ------------------------------------------------------- the block engine API --
--
-- What PVP borrows. Everything here already existed for the classic game and was
-- only ever missing a lane to be told about — which is why the mode could be
-- built on this engine instead of beside it, and why there is exactly one
-- implementation of a bomb, a fire, a settle and the play plane in the codebase.
--
-- `dealPiece`, `dropPiece` and `applyPlacement` are further up, next to the
-- classic wrappers that call them.

-- The piece this player is aiming, or nil.
function TowerService.heldOf(player: Player): Held?
	return heldBy[player]
end

-- Lift this player's piece if their lane has grown under it. Returns whether it
-- moved, so a caller polling every lane knows whether the state is worth sending.
function TowerService.reseatFor(player: Player, down: boolean?): boolean
	local piece = heldBy[player]
	if piece == nil then
		return false
	end
	return reseatPiece(piece, down == true)
end

-- Take back a piece somebody is still aiming, without dropping it.
--
-- The distinction matters at the end of a match: a piece released when the clock
-- stops is a block that keeps climbing while the standings are being read, so the
-- last moment of a round would decide it. Their client sees the piece go and
-- tears its own preview down, exactly as it does when a checkpoint takes one.
function TowerService.cancelPiece(player: Player)
	local piece = heldBy[player]
	if piece == nil then
		return
	end
	heldBy[player] = nil
	piece.model:Destroy()
end

-- The scoring height of one lane, in studs above the floor it stands on.
function TowerService.laneHeight(laneX: number, floorY: number): number
	return measureLane(laneX, floorY)
end

-- One bolt into the column at `x`, standing on `floorY`, announced on `source`.
--
-- The storm's own driver above is the classic run's; this is the same bolt with
-- its three assumptions made into arguments, so PVP can point one at each lane
-- from its own clock (see `PvpService`). What it hits is resolved *here*, at
-- strike time, rather than when the warning went up — seconds of building under
-- a marker count.
--
-- No lane check of its own, and it doesn't need one: `blastAt` reaches
-- LIGHTNING_RADIUS (26) and lanes are LANE_SPACING (120) apart, so a bolt aimed
-- into one lane cannot touch the tower in the next. That is the same arithmetic
-- that lets a Lightning *block* be safe in a match.
function TowerService.strikeColumn(x: number, floorY: number, source: Instance?)
	strikeLightning(highestAt(x, floorY), nil, source)
end

-- How many blocks are standing in one lane. Walks the list rather than keeping a
-- per-lane counter: blocks leave through six different paths (burnt out, fallen
-- off, blasted, destroyed with their model) and a counter maintained across all
-- of them is a counter that eventually drifts.
function TowerService.laneBlockCount(laneX: number): number
	local count = 0
	for _, block in blocks do
		if block.laneX == laneX and block.root.Parent ~= nil then
			count += 1
		end
	end
	return count
end

-- Take one lane off the board: the piece anyone is aiming over it, and every
-- block standing in it. Used when a match ends and when a lane is retired.
--
-- Destroys rather than blasts. The wreck is the classic storm's language, and it
-- would need somewhere to fall that isn't through five other lanes' towers.
function TowerService.clearLane(laneX: number)
	for player, piece in heldBy do
		if piece.laneX ~= laneX then
			continue
		end
		heldBy[player] = nil
		piece.model:Destroy()
	end
	for index = #blocks, 1, -1 do
		if blocks[index].laneX == laneX then
			removeBlockAt(index).model:Destroy()
		end
	end
end

-- Put the world into a zone from outside the classic checkpoint path, without
-- touching the classic state the HUD reads.
--
-- `setZone` above is the cmdr command's door and broadcasts the classic packet;
-- during a PVP match that packet is stale by definition, so the match sends the
-- zone on its own wire and calls this to make it true in the world.
function TowerService.applyZone(zoneId: number, sky: number)
	state.zoneId = zoneId
	state.zoneSky = sky
	applyZoneToTower()
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

	-- Put back anyone the inactivity check benched in an earlier session. The
	-- setting persists — it's a preference — so without this, being away for two
	-- turns once would greet them with a game that never deals them a piece and
	-- nothing on screen connecting the two. Spawned because the answer waits on
	-- the profile and a join shouldn't.
	task.spawn(function()
		if not TowerStatsService.consumeAutoAfk(player) or player.Parent ~= Players then
			return
		end
		SettingsService.set(player, Constants.SETTING_NOT_PLAYING, false)
	end)

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
	-- Idleness is a fact about this visit. A rejoin starts clean — including the
	-- first-turn grace, which someone coming back deserves as much as someone
	-- arriving for the first time.
	idleTurns[player] = nil
	turnsDealt[player] = nil
end

function TowerService.Start()
	if Constants.DISABLE_CHARACTERS then
		-- Stationary camera, no walking: an avatar would only be a physics prop
		-- standing under a falling tower.
		Players.CharacterAutoLoads = false
	end

	-- Before anything is built: `registerBlock` puts every block in a group, and a
	-- group that doesn't exist yet is an error per part rather than a warning.
	ensureCollisionGroups()

	buildArena()
	-- Zones own gravity (Space drops it to a sixth), so the run starts from the
	-- default rather than from whatever the place file was saved with.
	workspace.Gravity = Zones.gravityOf(state.zoneId)
	restartStormClock()

	Packets.Place.listen(function(payload, player)
		TowerService.applyPlacement(player, payload.x, payload.turns)
	end)
	Packets.Release.listen(function(payload, player)
		if heldBy[player] == nil then
			return
		end
		-- The drop carries its own placement so the piece falls exactly where the
		-- holder saw it, even if their last Place packet is still in flight.
		TowerService.applyPlacement(player, payload.x, payload.turns)
		-- Which drop this is depends on who's running the board. The classic
		-- `release` closes a turn as well as dropping a block, and a PVP lane has
		-- no turn to close — its own loop notices the piece went and deals the
		-- next one.
		if pvpActive then
			TowerService.dropPiece(player)
		else
			TowerService.release()
		end
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

	-- The session's first round is voted for like every other one. Parks the game
	-- (`intermission`) until the ballot resolves, so the poll below and `runTurns`
	-- both start against rules the players actually picked. Returns immediately —
	-- the waiting happens on its own thread.
	runOpeningVote()

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
