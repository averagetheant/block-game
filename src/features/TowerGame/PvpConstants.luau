-- PVP: the every-player-for-themselves round.
--
-- Classic TowerGame is one shared tower and a turn queue. PVP throws both away:
-- every player gets their own platform in their own lane, holds their own piece
-- at the same time as everyone else, and builds as high as they can before one
-- shared match clock runs out. There are no checkpoints, no storm and no turns —
-- the only score is how tall your own tower is when the timer stops.
--
-- These are its numbers. They live in their own file rather than in
-- `Constants.luau` because none of them mean anything to the classic game and
-- mixing them in would leave every reader of either mode wondering which half of
-- the file applied to them. The two files never disagree: anything shared (block
-- size, steering limit, plane, physics, spawn clearance) is read from
-- `Constants` here rather than restated.
--
-- Plain .luau => ReplicatedStorage, readable from both realms.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)

local PvpConstants = {
	-- ----------------------------------------------------------------- lanes --
	-- Hard cap on lanes, and therefore on how many players can be *playing* at
	-- once. It is not the server's player cap: `Players.MaxPlayers` is a place
	-- setting and can't be written at runtime, so that has to be set to 6 in
	-- Game Settings (see docs/game/TowerGamePvp.md). This number is what the
	-- lane layout is drawn from, and a seventh player would simply find no free
	-- slot — which is the honest failure mode either way.
	MAX_LANES = 6,
	-- Distance between lane centres, in studs.
	--
	-- Read it against the two things that can cross a lane boundary. A piece
	-- steers to ±STEER_LIMIT_X (22) and overhangs half a block past that, so a
	-- tower is about 52 studs wide; a bomb throws everything within
	-- EXPLOSION_RADIUS (36) of itself. 120 leaves ~68 studs of air between two
	-- towers, which is more than a blast on the near edge of one lane can reach
	-- into the next. Nobody may wreck a neighbour's tower — that is the whole
	-- reason lanes are this far apart rather than merely not overlapping.
	--
	-- It also sets how wide the map shot has to be: six lanes at 120 is 600
	-- studs across, which fits inside MAP_MAX_DISTANCE at every aspect ratio.
	LANE_SPACING = 120,
	-- Lane platforms sit at the same altitude as the classic base, so the two
	-- modes frame identically and a map built around the arena still works.
	LANE_Y = Constants.BASE_POSITION.Y,
	-- The same slab the classic base and every checkpoint uses: a lane is
	-- visibly the same building, just one of six.
	LANE_PLATFORM_SIZE = Constants.PLATFORM_SIZE,
	LANE_PLATFORM_COLOR = Constants.BASE_COLOR,
	-- Folder the lanes are parented under, inside the arena folder. One folder
	-- rather than loose children so teardown is a single Destroy and a stray
	-- lane can never be mistaken for a held piece by `findOwnPiece`, which walks
	-- the arena's *children* looking for the piece stamped with its own user id.
	LANES_FOLDER = "PvpLanes",

	-- ------------------------------------------------------------ the match --
	-- One shared clock for the whole round. Three minutes is about forty pieces
	-- a player at PIECE_SECONDS + PIECE_GAP_SECONDS — long enough that a bad
	-- start is recoverable, short enough that a mode with no checkpoints doesn't
	-- outstay its welcome.
	MATCH_SECONDS = 180,
	-- The beat before the first piece: lanes are already standing and the camera
	-- has landed on yours, so this is the moment to look at what you're building
	-- on and who you're up against.
	COUNTDOWN_SECONDS = 5,
	-- How long the final standings stay up before the round hands back to the
	-- gamemode vote.
	RESULTS_SECONDS = 12,
	-- How long the towers are left standing after the clock stops, before the
	-- board is cleared. The results panel is over the top of it — the point is
	-- that you can see the tower the number belongs to.
	FREEZE_SECONDS = 2,

	-- ----------------------------------------------------------- the pieces --
	-- Drop clock. Longer than a classic turn (15) on purpose: nobody is waiting
	-- on you, so the clock is only there to stop a player parking a piece over
	-- their tower forever, not to keep a queue moving.
	PIECE_SECONDS = 20,
	-- Beat between a piece landing and the next one appearing. Much shorter than
	-- the classic SETTLE_SECONDS (1.5) — that gap exists to let the room watch
	-- the tower settle before the next player is up, and in PVP there is no next
	-- player. Tempo is the mode.
	PIECE_GAP_SECONDS = 0.5,
	-- Odds any given piece is a special (bomb, burning, ghost, …): what a piece
	-- dealt at the whistle rolls against, and what one dealt after the ramp has
	-- topped out rolls against. Read through `specialChanceAt` below, not
	-- directly.
	--
	-- Not the classic escalating curve. That one is a function of checkpoints
	-- cleared, and a PVP match clears none, so it would sit at its 3% floor for
	-- the whole three minutes. This is PVP's own ramp, on PVP's own clock.
	--
	-- Rising rather than flat because the mode's shape is rising: the towers that
	-- are going to win are tall by the last minute, and a hazard costs more the
	-- taller the thing it lands on. Opening at 20% leaves the first minute about
	-- learning to aim; closing at 30% makes the finish the part worth watching.
	-- Both ends bypass `BlockTypes.MAX_CHANCE` (0.4) the same way the Roulette
	-- gamemode's number does — see `blockTypeChance` in Gamemodes.luau.
	SPECIAL_CHANCE_START = 0.2,
	SPECIAL_CHANCE_END = 0.3,
	-- How far through the match the ramp arrives at SPECIAL_CHANCE_END, as a
	-- fraction of MATCH_SECONDS. Short of 1 on purpose: "near the end" has to be
	-- long enough to actually play in, and a ramp that only landed on the final
	-- whistle would deliver its top rate to nobody. At 0.85 of a 180-second match
	-- the last ~27 seconds run flat out.
	SPECIAL_CHANCE_FULL_AT = 0.85,

	-- ------------------------------------------------------------- the zones --
	-- How long a zone lasts before the next one is rolled. The classic game
	-- changes zone when a checkpoint is cleared, which PVP has none of, so the
	-- zone is on a clock instead — about five zones over a match.
	ZONE_SECONDS = 35,
	-- The first zone of a match is always the plain one, so the first thirty
	-- seconds are spent learning the mode rather than the weather.
	FIRST_ZONE_NORMAL = true,
	-- The roll window: how long the next zone is *announced* before it becomes
	-- true in the world. The HUD spends it spinning a reel through the zone names
	-- (see `ZoneReel`) and lands on the answer at the far end of it.
	--
	-- The delay is the whole point rather than a cost of the animation: without
	-- it the sky would change while the reel was still spinning, which spoils the
	-- reveal and — worse — moves the ground under a piece somebody is aiming with
	-- no notice. Both realms hold off for the same window, and the exact moment
	-- rides the packet as `zoneAt` so a slow connection lands with everyone else.
	--
	-- Kept short. It's a beat of anticipation, not an interruption, and every
	-- second of it is a second of the zone's own 35 that nobody is playing.
	ZONE_ROLL_SECONDS = 2,

	-- ------------------------------------------------------------- the storm --
	-- Lightning, while a Stormy zone is up. The match runs its own driver rather
	-- than the classic one (see `PvpService.updateStrikes`), for one reason:
	-- **every lane is struck on the same clock**. Six players are building at
	-- once, and a storm that picked one spot on the board would be a coin toss
	-- deciding a match — one player losing two floors to weather while the lane
	-- beside them never hears thunder. Same beat, same count, one bolt each,
	-- somewhere random inside their own lane.
	--
	-- Its own cadence numbers rather than the classic ones, because it's pacing
	-- something different. `Constants.LIGHTNING_*` are written against a
	-- five-minute stage: a ten-second warning and a 14-22 second gap. A PVP zone
	-- lasts ZONE_SECONDS (35), so that cadence would spend most of a Stormy zone
	-- waiting and land about one bolt in it.
	--
	-- How long the red column stands before the bolt does. Shorter than the
	-- classic ten: there's no turn queue to sit through here, so five seconds is
	-- two or three pieces' worth of time to build somewhere else or to decide the
	-- tower is worth defending.
	STRIKE_WARNING_SECONDS = 5,
	-- The randomised gap between bolts, measured from the last one — the warning
	-- sits inside it, so raising a marker doesn't quietly slow the storm down.
	-- About two or three strikes per Stormy zone.
	STRIKE_MIN_SECONDS = 9,
	STRIKE_MAX_SECONDS = 14,

	-- ------------------------------------------------------------ the camera --
	-- Extra air around the whole board in the map shot (the HUD's camera button).
	MAP_PADDING = 50,
	-- Ceiling on how far back the map shot may stand. Higher than the classic
	-- CAMERA_MAX_DISTANCE (420) because this shot has to fit six lanes across
	-- rather than one tower, and on a portrait phone the horizontal axis is what
	-- decides the distance.
	MAP_MAX_DISTANCE = 700,
	-- Floor on the map shot's framed height, so a board of six one-block towers
	-- isn't shown from orbit.
	MAP_MIN_HEIGHT = 60,

	-- --------------------------------------------------------------- rewards --
	-- Paid at the end of the match, per stud of the player's own tower. Their
	-- tower, their studs — unlike the classic per-stud award, which pays whoever
	-- happened to place the block that set a shared record.
	CASH_PER_STUD = 3,
	-- Flat bonus for the tallest tower. Small next to the per-stud award: the
	-- height is the prize, and a winner-takes-all purse would make the last
	-- thirty seconds pointless for everyone but the leader.
	CASH_WINNER = 150,

	-- ---------------------------------------------------------------- phases --
	-- Broadcast as a uint8 on the PVP state packet. Deliberately its own enum
	-- rather than more entries on `Constants.PHASE`: the classic phases describe
	-- a turn queue and a storm, neither of which exists here, and one union of
	-- both would leave every reader checking which mode a value belonged to.
	PHASE = {
		-- No match running. The classic game owns the world.
		OFF = 0,
		-- Lanes are up, the first pieces haven't been dealt.
		COUNTDOWN = 1,
		-- The match clock is running.
		PLAYING = 2,
		-- The clock has stopped and the standings are up.
		RESULTS = 3,
	},

	-- Which surfaces this mode renders. Same convention as
	-- `Constants.Presentations`; see docs/game/presentations.md.
	Presentations = {
		-- The PVP HUD (match clock, your height, the standings strip). Off means
		-- the mode is playable but unnarrated, which is only useful for testing
		-- the camera.
		hud = true,
	},
}

-- The odds a piece dealt `progress` of the way through the match is a special.
-- 0 is the whistle, 1 is time. Linear from SPECIAL_CHANCE_START to
-- SPECIAL_CHANCE_END, which it reaches at SPECIAL_CHANCE_FULL_AT and holds for
-- the rest of the match.
--
-- A function next to the numbers rather than arithmetic at the call site, for the
-- reason `BlockTypes.chanceAt` lives next to its own: the rate and the roll can't
-- drift apart if reading the rate is reading this.
--
-- Clamped at both ends, so a caller that hands it a progress off the clock — a
-- piece dealt during the countdown, or one dealt a tick after time — gets an end
-- of the ramp rather than an extrapolation off it.
function PvpConstants.specialChanceAt(progress: number): number
	local ramp = math.clamp(progress / PvpConstants.SPECIAL_CHANCE_FULL_AT, 0, 1)
	local span = PvpConstants.SPECIAL_CHANCE_END - PvpConstants.SPECIAL_CHANCE_START
	return PvpConstants.SPECIAL_CHANCE_START + span * ramp
end

return PvpConstants
