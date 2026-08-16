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

return {
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
	-- EXPLOSION_RADIUS (46) of itself. 120 leaves ~68 studs of air between two
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
	-- Odds any given piece is a special (bomb, burning, ghost, …). A flat chance
	-- rather than the classic escalating curve: a PVP round is three minutes
	-- long and has no checkpoints to escalate against, so the curve would spend
	-- the whole match at its 3% floor. This bypasses `BlockTypes.MAX_CHANCE` the
	-- same way the Roulette gamemode's does — see `blockTypeChance` in
	-- Gamemodes.luau, which is the field this is fed through.
	SPECIAL_CHANCE = 0.3,

	-- ------------------------------------------------------------- the zones --
	-- How long a zone lasts before the next one is rolled. The classic game
	-- changes zone when a checkpoint is cleared, which PVP has none of, so the
	-- zone is on a clock instead — about five zones over a match.
	ZONE_SECONDS = 35,
	-- The first zone of a match is always the plain one, so the first thirty
	-- seconds are spent learning the mode rather than the weather.
	FIRST_ZONE_NORMAL = true,

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
