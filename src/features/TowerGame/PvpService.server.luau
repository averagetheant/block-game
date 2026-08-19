-- PVP: six lanes, six towers, one clock.
--
-- Owns a *match* — the lanes, who is in one, the pieces they're each aiming, the
-- zone rolling over the top, and the standings at the end. It owns none of what a
-- block does: pieces are built, dropped, settled, burnt, blasted and held to the
-- play plane by TowerService's block engine, which this file drives one lane at a
-- time through `dealPiece` / `dropPiece` / `laneHeight`.
--
-- That split is the whole design. Every hazard in the game is already spatial —
-- a bomb has a radius, a fire spreads by contact, glue welds what it's touching —
-- so a second tower two hundred studs away needs no new rule to be safe from the
-- first. Lanes are set far enough apart (PvpConstants.LANE_SPACING) that nothing
-- can reach across one, and with that one guarantee the entire block engine works
-- unchanged for six towers at once. There is exactly one bomb in this codebase.
--
-- The mode is entered by winning the gamemode vote, not by a place setting:
-- `TowerService.runRoundBreak` sees `stage.pvp`, hands the board over here, waits
-- for `runMatch` to return, and puts the vote back up. So PVP is a round like any
-- other round, and picking it twice plays two matches.
--
--   countdown → lanes are standing, nobody has a piece yet
--   playing   → every lane deals itself pieces on its own clock
--   results   → the towers stay up, the standings go over them
--
-- What this file deliberately does not have: turns, a queue, a storm, checkpoints,
-- a target height, or any notion of the room doing something together. The only
-- score is how tall your own tower is when the clock stops.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)
local PvpConstants = require(ReplicatedStorage.Features.TowerGame.PvpConstants)
local PvpLanes = require(ReplicatedStorage.Features.TowerGame.PvpLanes)
local PvpPackets = require(ReplicatedStorage.Features.TowerGame.PvpPackets)
local Zones = require(ReplicatedStorage.Features.TowerGame.Zones)

local CashService = require(script.Parent.CashService)
local TowerService = require(script.Parent.TowerService)
local TowerStatsService = require(script.Parent.TowerStatsService)

local PHASE = PvpConstants.PHASE

type Lane = {
	-- Fixed seat, 0 … MAX_LANES - 1. Never reused while the lane is live, so a
	-- tower can't change position under the camera watching it.
	slot: number,
	-- The seat's world X, from `PvpLanes.xOf`. Also the lane id every block and
	-- held piece is tagged with in the block engine.
	x: number,
	-- Top surface of the platform, i.e. what a height of 0 means here.
	floorY: number,
	player: Player,
	-- Kept beside `player` so a lane can still be listed in the standings after
	-- its player has gone: `player.UserId` on a departed Player is not something
	-- to rely on, and the results are about who played, not who is still here.
	userId: number,
	platform: BasePart,
	height: number,
	blockCount: number,
	-- When the next piece is due. 0 means "they're holding one, or one is being
	-- dealt" — the gap is started by the poll the first time it finds the lane
	-- empty, which is what makes a manual drop and an expired clock feel the
	-- same.
	nextPieceAt: number,
	-- When the piece they're aiming drops itself. 0 when nothing is held.
	pieceEndsAt: number,
}

local PvpService = {}

-- After TowerService (20): this drives that file's block engine, so it must not
-- be able to run a match against an arena that hasn't been built yet.
PvpService.Priority = 21

local lanes: { Lane } = {}
local laneOf: { [Player]: Lane } = {}

-- Lanes are parented under one folder so teardown is a single Destroy, and — more
-- importantly — so a platform is never a *child of the arena*. The holder's
-- client finds its own piece by walking the arena's children looking for a model
-- stamped with its user id (`TowerAimController.findOwnPiece`); keeping six
-- platforms out of that walk keeps the lookup exactly as cheap as it was.
local folder: Folder? = nil

local phase = PHASE.OFF
local endsAt = 0
local zoneId = Zones.DEFAULT_ID
local zoneSky = 1
local zoneRollAt = 0
-- When the announced zone becomes true in the world, server time. Equal to "now"
-- for a zone that landed the instant it was rolled; up to ZONE_ROLL_SECONDS ahead
-- while the reel is spinning on every client.
local zoneAt = 0
-- Bumped by every roll, so the deferred apply below can tell whether it is still
-- the newest one. A pending apply that fires after the match has ended — or after
-- a second roll somehow overtook it — would be writing gravity for a zone nobody
-- is in any more.
local zoneToken = 0
local lastBroadcast = 0
-- Set while `runMatch` is winding down, so the poll stops dealing pieces the
-- instant the clock stops rather than one tick later.
local dealing = false

-- The storm's clock, while a Stormy zone is up. One clock for the whole board:
-- every live lane is warned together and struck together, so weather can't be
-- the thing that decided a match. See STRIKE_* in PvpConstants.
--
-- When the next bolt lands (`os.clock`), and the X each pending bolt is aimed at,
-- keyed by the **platform** that announced it. `pendingStrikes` is empty whenever
-- no warning is up, which is also the "nothing to clear" test.
--
-- Keyed by the platform rather than by the lane's slot because a slot can change
-- hands inside a warning window: a lane retires, the seat is freed, and the next
-- player through the door is seated in it. Keyed by slot, that player would take a
-- bolt from a warning they never saw; keyed by the platform (a fresh part every
-- time a lane is granted) they simply aren't in this round of strikes.
local nextStrikeAt = 0
local strikeDueAt = 0
local pendingStrikes: { [BasePart]: number } = {}
-- Whether the storm is currently running. Its rising edge is what starts the
-- first gap of a Stormy zone rather than the first warning.
local storming = false

-- ------------------------------------------------------------------- the wire --

local function broadcast()
	local payload = {
		phase = phase,
		endsAt = endsAt,
		matchSeconds = PvpConstants.MATCH_SECONDS,
		zoneId = zoneId,
		zoneSky = zoneSky,
		zoneAt = zoneAt,
		lanes = {},
	}

	for _, lane in lanes do
		local piece = TowerService.heldOf(lane.player)
		table.insert(payload.lanes, {
			userId = lane.userId,
			slot = lane.slot,
			height = lane.height,
			blockCount = lane.blockCount,
			holding = piece ~= nil,
			pieceTop = if piece then TowerService.pieceTopOf(piece) else 0,
			pieceEndsAt = if piece then lane.pieceEndsAt else 0,
			shapeId = if piece and piece.shape then piece.shape.id else 0,
			blockTypeId = if piece and piece.blockType then piece.blockType.id else 0,
		})
	end

	PvpPackets.State.sendToAll(payload)
	lastBroadcast = os.clock()
end

-- Tell every client the mode is over and the classic game owns the world again.
-- Sent rather than simply stopping: a client that only ever *stopped* hearing
-- from us would keep its last match on screen forever, and "the HUD never went
-- away" is indistinguishable from the server having died.
local function broadcastOff()
	phase = PHASE.OFF
	endsAt = 0
	-- Retires a roll still inside its window (the clock can hand out a zone in the
	-- last two seconds of a match). See `rollZone`.
	zoneToken += 1
	PvpPackets.State.sendToAll({
		phase = phase,
		endsAt = 0,
		matchSeconds = PvpConstants.MATCH_SECONDS,
		zoneId = zoneId,
		zoneSky = zoneSky,
		zoneAt = zoneAt,
		lanes = {},
	})
end

-- ------------------------------------------------------------------ the lanes --

local function buildPlatform(slot: number): BasePart
	local part = Instance.new("Part")
	part.Name = `Lane{slot}`
	part.Anchored = true
	part.Size = PvpConstants.LANE_PLATFORM_SIZE
	part.Position = Vector3.new(PvpLanes.xOf(slot), PvpConstants.LANE_Y, Constants.PLANE_Z)
	part.Color = PvpConstants.LANE_PLATFORM_COLOR
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	-- The same floor the classic base is, for the same reason it is one: a Bouncy
	-- piece landing on a bare lane used to bounce off the platform itself, and a
	-- lane is bare far more often than the classic tower ever is. See FLOOR_PHYSICS.
	part.CustomPhysicalProperties = Constants.FLOOR_PHYSICS
	-- Left in the Default collision group on purpose, exactly like the classic
	-- base and the checkpoint platforms: a Ghost falls through blocks and *not*
	-- through the floor, and a lane platform is floor.
	part.Parent = folder
	return part
end

local function freeSlot(): number?
	local taken: { [number]: boolean } = {}
	for _, lane in lanes do
		taken[lane.slot] = true
	end
	for slot = 0, PvpConstants.MAX_LANES - 1 do
		if not taken[slot] then
			return slot
		end
	end
	return nil
end

-- Put a player in the match. Returns nil when there's no seat left, which is the
-- only way this fails.
local function grantLane(player: Player): Lane?
	local slot = freeSlot()
	if slot == nil then
		return nil
	end

	local platform = buildPlatform(slot)
	local lane: Lane = {
		slot = slot,
		x = PvpLanes.xOf(slot),
		floorY = platform.Position.Y + platform.Size.Y / 2,
		player = player,
		userId = player.UserId,
		platform = platform,
		height = 0,
		blockCount = 0,
		-- Dealt on the next poll rather than here, so a lane granted mid-match
		-- and a lane granted at the countdown come into play through one path.
		nextPieceAt = workspace:GetServerTimeNow(),
		pieceEndsAt = 0,
	}
	table.insert(lanes, lane)
	laneOf[player] = lane
	return lane
end

-- Take a lane off the board and destroy what was built in it.
--
-- Only ever called for a player who has *left*. A player who stops playing keeps
-- their lane for the rest of the match — see `stepLanes`.
local function retireLane(lane: Lane)
	local index = table.find(lanes, lane)
	if index then
		table.remove(lanes, index)
	end
	laneOf[lane.player] = nil
	TowerService.clearLane(lane.x)
	lane.platform:Destroy()
end

-- ----------------------------------------------------------------- the pieces --

-- How far through the match clock we are: 0 at the whistle, 1 at time.
--
-- Any phase but PLAYING reads 0. `endsAt` belongs to the countdown or to the
-- results panel then, and a piece dealt against that clock would take its odds
-- from a number that has nothing to do with how far along the match is.
local function matchProgress(): number
	if phase ~= PHASE.PLAYING then
		return 0
	end
	local left = endsAt - workspace:GetServerTimeNow()
	return math.clamp(1 - left / PvpConstants.MATCH_SECONDS, 0, 1)
end

local function dealTo(lane: Lane)
	-- The hazard rate is read here, as the piece is built, rather than once at the
	-- whistle: the whole point of the ramp is that a piece dealt in the last
	-- minute rolls against a worse number than one dealt in the first, and six
	-- lanes are dealing at their own tempos throughout.
	TowerService.dealPiece(
		lane.player,
		lane.x,
		lane.floorY,
		PvpConstants.specialChanceAt(matchProgress())
	)
	lane.nextPieceAt = 0
	lane.pieceEndsAt = workspace:GetServerTimeNow() + PvpConstants.PIECE_SECONDS
end

-- Everything one poll does to one lane: measure it, keep the piece above it, and
-- hand out the next piece when it's due.
local function stepLane(lane: Lane, now: number): boolean
	-- Heights are frozen once the clock stops. The standings on screen and the
	-- standings the rewards were paid against have to be the same numbers, and a
	-- block settling a second after time would otherwise move one and not the
	-- other.
	if phase == PHASE.RESULTS then
		return false
	end

	local height = TowerService.laneHeight(lane.x, lane.floorY)
	local count = TowerService.laneBlockCount(lane.x)
	local changed = math.abs(height - lane.height) > Constants.HEIGHT_EPSILON or count ~= lane.blockCount
	lane.height = height
	lane.blockCount = count

	-- Lift the piece if the tower has grown under it. Same rule as the classic
	-- game's, applied per lane: only ever upward, because a piece sinking
	-- mid-aim reads as a glitch and would drop the player into a gap that has
	-- since been filled.
	if TowerService.reseatFor(lane.player) then
		changed = true
	end

	if not dealing then
		return changed
	end

	local piece = TowerService.heldOf(lane.player)
	if piece == nil then
		-- Start the gap the first time we find the lane empty. Doing it here
		-- rather than at the drop is what makes a player pressing DROP and a
		-- clock running out feel identical — neither has to remember to book the
		-- next piece, and neither can book it twice.
		if lane.nextPieceAt == 0 then
			lane.nextPieceAt = now + PvpConstants.PIECE_GAP_SECONDS
			lane.pieceEndsAt = 0
			changed = true
		end
		if now >= lane.nextPieceAt then
			dealTo(lane)
			changed = true
		end
		return changed
	end

	-- The drop clock. It exists to stop a piece hanging over a tower forever, not
	-- to keep a queue moving — nobody is waiting on this player.
	if now >= lane.pieceEndsAt then
		TowerService.dropPiece(lane.player)
		changed = true
	end
	return changed
end

-- Anyone who should be in the match but isn't yet: someone who joined mid-round,
-- and someone who turned "Not playing" back off.
--
-- Both are the same question asked every poll rather than two event handlers,
-- because they're the same answer: a seat is free and this player wants one. It
-- also means a player who joins during the countdown and one who joins with
-- thirty seconds left come into play through one path.
--
-- Note what is *not* here: nothing takes a lane away when "Not playing" goes
-- back on. Deliberately — see the note in `stepLanes`'s caller and the doc.
local function admitWaiting()
	if not dealing then
		return
	end
	for _, player in Players:GetPlayers() do
		if laneOf[player] ~= nil or TowerService.isSpectating(player) then
			continue
		end
		if grantLane(player) == nil then
			-- No seat. Every later player will find the same, so stop asking.
			return
		end
	end
end

-- ------------------------------------------------------------------ the zones --

-- Roll the next zone, announce it, and make it true a beat later.
--
-- The two halves are deliberately apart. `zoneId` goes on the wire immediately,
-- which is what starts every client's reel; the world only changes when the reel
-- lands, ZONE_ROLL_SECONDS later. Nothing can be acted on in between — the
-- announcement changes no rule, only what the HUD is spinning — so the gap costs
-- the players nothing and buys the change an entrance.
--
-- `first` skips the window: the opening zone arrives with the world during the
-- countdown, so there is nothing to reveal and no tower yet to disturb.
local function rollZone(first: boolean)
	local zone = if first and PvpConstants.FIRST_ZONE_NORMAL
		then Zones.get(Zones.DEFAULT_ID)
		else Zones.roll(zoneId)
	zoneId = zone.id
	-- An arbitrary number, not an index: the server has no idea how many skies
	-- exist (they're a Studio asset it can't see) and the client takes it modulo
	-- the folder count. Same contract as the classic packet's.
	zoneSky = math.random(1, 255)
	zoneRollAt = os.clock() + PvpConstants.ZONE_SECONDS

	-- Makes it true in the world — gravity, snow friction, retro studs — without
	-- touching the classic state packet, which is stale for the whole match.
	local landing, sky = zoneId, zoneSky
	zoneToken += 1
	local token = zoneToken

	local window = if first then 0 else PvpConstants.ZONE_ROLL_SECONDS
	zoneAt = workspace:GetServerTimeNow() + window
	if window <= 0 then
		TowerService.applyZone(landing, sky)
		return
	end

	task.delay(window, function()
		-- A newer roll, or the match ending, retires this one. Both bump the
		-- token, and the classic round takes the world back the moment the match
		-- is over — a stale apply landing after that would drop the next run into
		-- low gravity for no reason anybody could see.
		if token ~= zoneToken then
			return
		end
		TowerService.applyZone(landing, sky)
	end)
end

-- ------------------------------------------------------------------ the storm --

-- Lightning, for a board with six towers on it.
--
-- The classic driver (`TowerService.updateLightning`) picks one spot on the play
-- plane and warns it. That is exactly right for one shared tower and exactly
-- wrong here: whichever lane happened to be under the X would take the damage and
-- the other five would watch. So the match runs its own clock and strikes **every
-- live lane at once** — same beat, one bolt each, at a random X inside each
-- lane's own steering range. The storm is weather everybody is standing in rather
-- than a coin toss about who loses a tower.
--
-- Each bolt is announced on its own lane's platform (see
-- `TowerService.strikeColumn`), which is what lets six markers and six flashes
-- exist at once: one attribute on one arena folder can only describe one of them,
-- and the platform is also the floor the client stands the marker's column on.

-- Take every marker down. Called when the bolts land, when the zone stops being
-- stormy under a standing warning, and at teardown — a red column outliving the
-- match it belonged to would stand over the classic round that follows.
local function clearStrikeMarkers()
	if next(pendingStrikes) == nil then
		return
	end
	for platform in pendingStrikes do
		-- A platform destroyed with its lane took its marker with it; the client
		-- clears any column whose announcer has left the world.
		if platform.Parent ~= nil then
			platform:SetAttribute(Constants.WARN_ATTRIBUTE, nil)
		end
	end
	table.clear(pendingStrikes)
end

local function randomGap(): number
	return PvpConstants.STRIKE_MIN_SECONDS
		+ math.random() * (PvpConstants.STRIKE_MAX_SECONDS - PvpConstants.STRIKE_MIN_SECONDS)
end

local function updateStrikes(now: number)
	-- Three things have to be true, and each rules out a bolt that would land at
	-- a moment nobody could read:
	--
	--   * pieces are being dealt — a bolt during the countdown would hit bare
	--     platforms, and one during the results would rearrange the towers the
	--     standings are being read off;
	--   * the zone is Stormy;
	--   * and it has actually *landed*. `zoneId` goes on the wire up to
	--     ZONE_ROLL_SECONDS before the world takes it, while every client's reel
	--     is still spinning — a warning column going up mid-spin would give the
	--     answer away before the reel did.
	local live = dealing
		and Zones.get(zoneId).kind == "stormy"
		and workspace:GetServerTimeNow() >= zoneAt

	if not live then
		clearStrikeMarkers()
		storming = false
		return
	end

	-- First tick of a Stormy zone: start the gap rather than the warning. The
	-- clock is carried between zones otherwise, and a zone that arrives with an
	-- expired one would open with a marker already standing.
	if not storming then
		storming = true
		nextStrikeAt = now + randomGap()
		return
	end

	if next(pendingStrikes) ~= nil then
		if now < strikeDueAt then
			return
		end

		-- Markers off first, bolts second: a client that sees both attributes
		-- change in the same frame should be left with a flash and no column,
		-- never the other way round.
		local aimed = table.clone(pendingStrikes)
		clearStrikeMarkers()
		nextStrikeAt = now + randomGap()

		for _, lane in lanes do
			local x = aimed[lane.platform]
			-- A lane seated *during* the warning isn't in this list and doesn't get
			-- struck: nobody may be hit by a bolt they were never shown. It'll be
			-- warned with everyone else on the next one.
			if x == nil then
				continue
			end
			TowerService.strikeColumn(x, lane.floorY, lane.platform)
		end
		return
	end

	-- Nothing pending: raise the next round of warnings once the gap has run
	-- down, minus the warning it has to fit inside.
	if now < nextStrikeAt - PvpConstants.STRIKE_WARNING_SECONDS then
		return
	end

	strikeDueAt = now + PvpConstants.STRIKE_WARNING_SECONDS
	for _, lane in lanes do
		-- Inside the lane's own steering range, so a bolt always lands somewhere
		-- its player could have built — and never in the air between two lanes.
		local x = lane.x + (math.random() * 2 - 1) * Constants.STEER_LIMIT_X
		pendingStrikes[lane.platform] = x
		-- Only the X goes out. What the bolt actually hits is resolved when it
		-- lands, so five seconds of building under the marker counts, and the
		-- client stands the column on the platform that announced it.
		lane.platform:SetAttribute(Constants.WARN_ATTRIBUTE, x)
	end
end

-- --------------------------------------------------------------- the standings --

-- The lanes sorted tallest first. The order the results panel draws and the
-- order the rewards are paid in.
local function standings(): { Lane }
	local sorted = table.clone(lanes)
	table.sort(sorted, function(a, b)
		return a.height > b.height
	end)
	return sorted
end

local function payOut(sorted: { Lane })
	for rank, lane in sorted do
		local player = lane.player
		if player.Parent ~= Players then
			continue
		end

		-- Their tower, their studs. Unlike the classic per-stud award, which pays
		-- whoever happened to place the block that set a shared record, this is
		-- paid to the person who built the thing being measured.
		local earned = math.floor(lane.height * PvpConstants.CASH_PER_STUD)
		if rank == 1 and lane.height > 0 then
			earned += PvpConstants.CASH_WINNER
		end
		if earned > 0 then
			CashService.award(player, earned, "Pvp")
		end

		-- A personal best, not the server's. The classic `recordHeight` credits
		-- everyone because there is one shared tower; in PVP the tower is yours
		-- and so is the record.
		TowerStatsService.recordPlayerHeight(player, lane.height)
	end
end

-- ----------------------------------------------------------------- the match --

local function teardown()
	-- Before the lanes go: the markers live on their platforms, and clearing an
	-- attribute on a destroyed part is a write nobody reads.
	clearStrikeMarkers()
	storming = false
	for index = #lanes, 1, -1 do
		retireLane(lanes[index])
	end
	table.clear(laneOf)
	if folder then
		folder:Destroy()
		folder = nil
	end
end

-- Hold here until `deadline`, polling the lanes.
--
-- One loop rather than a coroutine per lane. Six lanes at POLL_INTERVAL is a
-- trivial amount of work, and a single loop means the match has exactly one place
-- where time passes — so "the clock stopped" and "stop dealing pieces" can't end
-- up in different orders on different lanes.
local function runUntil(deadline: number)
	while workspace:GetServerTimeNow() < deadline do
		task.wait(Constants.POLL_INTERVAL)

		local now = workspace:GetServerTimeNow()
		local changed = false

		admitWaiting()
		for index = #lanes, 1, -1 do
			local lane = lanes[index]
			-- A player who left takes their tower with them. Their lane's blocks
			-- would otherwise stand for the rest of the match being measured for
			-- somebody who can't see them, and the seat should go to whoever is
			-- next through the door.
			if lane.player.Parent ~= Players then
				retireLane(lane)
				changed = true
				continue
			end
			if stepLane(lane, now) then
				changed = true
			end
		end

		if dealing and os.clock() >= zoneRollAt then
			rollZone(false)
			changed = true
		end

		-- Weather, on the same poll as everything else: the match has one place
		-- where time passes (see above), and the storm is not the thing to give a
		-- second one to.
		updateStrikes(os.clock())

		-- Re-send at least once a second even when nothing moved: a player who
		-- joined between broadcasts has no other way to learn there's a match on.
		if changed or os.clock() - lastBroadcast > 1 then
			broadcast()
		end
	end
end

-- Run one match. **Yields** for its whole length — the caller (the classic round
-- break) is parked behind it, which is what makes "PVP owns the board" true
-- rather than cosmetic.
function PvpService.runMatch()
	folder = Instance.new("Folder")
	folder.Name = PvpConstants.LANES_FOLDER
	folder.Parent = workspace:FindFirstChild(Constants.ARENA_NAME) or workspace

	-- Seats are handed out before the countdown so the players can see who they're
	-- up against, and so the camera has a lane to land on rather than drifting
	-- onto one five seconds in.
	dealing = true
	admitWaiting()
	dealing = false

	rollZone(true)

	phase = PHASE.COUNTDOWN
	endsAt = workspace:GetServerTimeNow() + PvpConstants.COUNTDOWN_SECONDS
	broadcast()
	runUntil(endsAt)

	phase = PHASE.PLAYING
	endsAt = workspace:GetServerTimeNow() + PvpConstants.MATCH_SECONDS
	-- The zone clock starts with the match, not with the countdown: the first
	-- zone should get its full run in play.
	zoneRollAt = os.clock() + PvpConstants.ZONE_SECONDS
	dealing = true
	broadcast()
	runUntil(endsAt)

	-- The clock has stopped. Nothing more is dealt, and every piece still in the
	-- air is taken back rather than dropped — a block released after time is a
	-- block that could still be climbing while the standings are being read.
	dealing = false
	for _, lane in lanes do
		TowerService.cancelPiece(lane.player)
	end

	-- A beat with the towers standing and no results over them, so the last block
	-- to land is seen landing. Heights stay live through it: a piece dropped in
	-- the final second is still in the air when the clock stops, and it counts if
	-- it comes to rest on the tower.
	runUntil(workspace:GetServerTimeNow() + PvpConstants.FREEZE_SECONDS)

	-- Now the numbers are final, and `stepLane` stops touching them — the board on
	-- screen and the board the rewards were paid against are one set of numbers.
	for _, lane in lanes do
		lane.height = TowerService.laneHeight(lane.x, lane.floorY)
	end
	phase = PHASE.RESULTS
	endsAt = workspace:GetServerTimeNow() + PvpConstants.RESULTS_SECONDS
	broadcast()

	local sorted = standings()
	payOut(sorted)

	runUntil(endsAt)

	teardown()
	broadcastOff()
end

-- Whether a match is running. Read by TowerService only through `stage.pvp`; this
-- is for anything else that needs to ask (a cmdr command, a later product).
function PvpService.isActive(): boolean
	return phase ~= PHASE.OFF
end

function PvpService.Start()
	-- A leaver's lane is retired by the poll, which is where every other lane
	-- change happens too. Nothing to bind here — but the hook has to exist for
	-- the Loader, and a service that quietly has no Start is one nobody can tell
	-- apart from a broken one.
end

return PvpService
