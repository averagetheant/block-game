--!strict
-- The gamemodes TowerGame puts on the ballot, and what each one does to the
-- stage that follows.
--
-- This is TowerGame's content, not GamemodeVote's: the vote feature owns the
-- poll and knows nothing about turn clocks. `Gamemode.luau` (the sibling
-- registration file) hands this list over; `TowerService` reads the winner's
-- `modifier` back and plays the stage by those numbers.
--
-- A modifier is a complete set of stage numbers rather than a diff, so there's
-- one place to look to know how a round will play and no compounding across
-- rounds. `DEFAULT` is the un-voted round — what the game did before any of
-- this existed, and what it falls back to when there's no vote (server start,
-- an aborted poll).
--
-- The vote runs between *rounds*, so a winning modifier holds for every stage of
-- the round that follows it — clearing a checkpoint doesn't re-roll the rules
-- mid-run. See `runRoundBreak` in TowerService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local assets = require(ReplicatedStorage.Shared.Boil).assets
local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)
local PvpConstants = require(ReplicatedStorage.Features.TowerGame.PvpConstants)

export type Modifier = {
	-- Seconds on a turn clock before the piece drops itself.
	turnSeconds: number,
	-- Seconds on the stage clock before the storm takes the tower.
	stormSeconds: number,
	-- Multiplier on the odds a piece is a special type (bomb / burning / Noob).
	-- 1 is the normal curve; the roll is still clamped by BlockTypes.MAX_CHANCE.
	blockTypeScale: number,
	-- Flat odds a piece is special, overriding the curve *and* its cap entirely.
	-- nil leaves `blockTypeScale` in charge. This exists because a mode like
	-- Roulette wants a promise ("70% of pieces are special") rather than a
	-- multiplier, and a multiplier can't make that promise — MAX_CHANCE would
	-- silently hold it at 0.4 however high the scale went.
	blockTypeChance: number?,
	-- Lightning strikes regardless of zone. Normally it's the Stormy zone's
	-- hazard; a mode can turn it on everywhere.
	alwaysLightning: boolean?,
	-- Every zone this round is a *special* one — the calm zone is taken out of the
	-- game. `Zones.next`'s cadence (two calm floors, then a twist) is replaced by
	-- `Zones.rollSpecial` on every checkpoint, and the round opens in a special
	-- rather than in Clear Skies: the first stage is the longest one, and starting
	-- it in plain weather would make the mode's promise wait five minutes to
	-- arrive. See `applyOpeningZone` in TowerService.
	specialsOnly: boolean?,
	-- This mode isn't a set of numbers for the classic round — it *replaces* the
	-- round. `TowerService.runRoundBreak` hands the board to `PvpService` and
	-- waits, then puts the vote back up rather than starting a classic run.
	--
	-- It's a flag rather than a fifth number because there is nothing to tune:
	-- the turn queue, the storm and the checkpoints all stop existing, and the
	-- two clocks below describe PVP's own piece and match timers only so the
	-- ballot card and the HUD have honest denominators to draw against.
	pvp: boolean?,
}

export type Gamemode = {
	id: string,
	name: string,
	icon: string,
	blurb: string?,
	order: number?,
	modifier: Modifier,
}

local Gamemodes = {}

Gamemodes.DEFAULT = {
	turnSeconds = Constants.TURN_SECONDS,
	stormSeconds = Constants.STORM_SECONDS,
	blockTypeScale = 1,
} :: Modifier

-- Two of the four ballot slots are permanent, and they're the two that aren't
-- twists on a round: **Classic** and **PVP**, the game's two ways to play. They
-- take orders 0 and 1 so they always draw as the left-hand pair, which leaves the
-- last two panels for the rolled twists — a player who wants either of the two
-- real modes learns one place to look instead of reading the ballot every round.
--
-- Everything below them is a variation on the classic round and rolls for those
-- two remaining slots (`BALLOT_SIZE`, GamemodeVote/Constants).
Gamemodes.List = {
	{
		id = "classic",
		name = "Classic",
		blurb = "The game, played straight.",
		icon = assets.Icons.book,
		order = 0,
		-- Always on the ballot. A vote whose options are all twists has no "leave
		-- it alone" answer, so the players couldn't decline a modifier — Classic is
		-- that answer, and a fixed position makes it the one panel you can pick
		-- without reading.
		pinned = true,
		-- Literally the un-voted numbers: winning Classic and skipping the vote
		-- have to land on the same round, or one of them is lying.
		modifier = Gamemodes.DEFAULT,
	},
	{
		id = "towerRush",
		name = "Tower Rush",
		blurb = "Beat a faster storm.",
		icon = assets.Icons.rocket,
		order = 2,
		-- The stage clock is the pressure, so this stage turns it up: two thirds
		-- of the usual window to reach the same target.
		modifier = {
			turnSeconds = Constants.TURN_SECONDS,
			stormSeconds = math.floor(Constants.STORM_SECONDS * 2 / 3),
			blockTypeScale = 1,
		},
	},
	{
		id = "blitz",
		name = "Blitz Builder",
		blurb = "Half the turn clock.",
		icon = assets.Icons.wheel,
		order = 3,
		-- Same stage, less thinking. The storm clock is left alone so the
		-- shortened turns actually buy the players more attempts, not fewer.
		modifier = {
			turnSeconds = math.max(5, math.floor(Constants.TURN_SECONDS / 2)),
			stormSeconds = Constants.STORM_SECONDS,
			blockTypeScale = 1,
		},
	},
	{
		id = "roulette",
		name = "Roulette",
		blurb = "70% of pieces are special.",
		icon = assets.Icons.questionMark,
		order = 4,
		-- A flat chance rather than a multiplier. The old Mystery Mode scaled the
		-- curve ×6, which sounds dramatic and wasn't: MAX_CHANCE held it at 0.4
		-- however high the scale went, so the mode's real behaviour didn't match
		-- what it promised. `blockTypeChance` bypasses both the curve and the cap
		-- so the number on the card is the number that happens.
		modifier = {
			turnSeconds = Constants.TURN_SECONDS,
			stormSeconds = Constants.STORM_SECONDS,
			blockTypeScale = 1,
			blockTypeChance = 0.7,
		},
	},
	{
		id = "lightningStorm",
		name = "Lightning Storm",
		blurb = "Lightning strikes in every zone.",
		icon = assets.Icons.rocket,
		order = 5,
		-- The Stormy zone's hazard, everywhere. It keeps its ten-second warning,
		-- so this is a round-long pressure rather than an unfair one.
		modifier = {
			turnSeconds = Constants.TURN_SECONDS,
			stormSeconds = Constants.STORM_SECONDS,
			blockTypeScale = 1,
			alwaysLightning = true,
		},
	},
	{
		id = "wildWeather",
		name = "Wild Weather",
		blurb = "Every zone bends a rule. No clear skies.",
		-- No weather icon in the kit, and the round's shape is the world turning
		-- over at every floor rather than any one hazard — so the cycle arrow is
		-- the nearest honest fit. Swap it the day `assets.Icons` grows a cloud.
		icon = assets.Icons.rebirth,
		order = 6,
		-- The numbers are Classic's. The whole mode is which zones may be picked,
		-- which is deliberately the *only* thing it changes: the zones already
		-- carry six different twists between them, and stacking a clock change on
		-- top would make it a second Tower Rush that also happened to snow.
		--
		-- It leans on the zone warnings to stay fair — every special announces
		-- itself in the banner before it bites — and on `avoidId` in
		-- `Zones.rollSpecial` so the same hazard can't land twice running.
		modifier = {
			turnSeconds = Constants.TURN_SECONDS,
			stormSeconds = Constants.STORM_SECONDS,
			blockTypeScale = 1,
			specialsOnly = true,
		},
	},
	{
		id = "pvp",
		name = "PVP",
		blurb = "Own platform. Build highest before the timer.",
		icon = assets.Icons.friends,
		-- Second panel, beside Classic: these two are the game's two ways to play,
		-- and neither is a twist on the other's round.
		order = 1,
		-- Permanent, like Classic. PVP is a mode players ask for by name, and a mode
		-- that only appears when the roll offers it is one they can't ask for — with
		-- two rolled slots out of five twists it was on about two ballots in five.
		pinned = true,
		-- The one mode on the ballot that isn't a variation on the round. The two
		-- clocks are PVP's own — the drop clock and the match clock — so the HUD
		-- and this card describe the mode that actually runs rather than a
		-- classic round nobody is going to play. `blockTypeChance` is the same
		-- lever Roulette uses, bypassing the escalating curve that a three-minute
		-- round with no checkpoints would never climb.
		--
		-- It carries PVP's *opening* rate only. Once a match is running the odds
		-- ramp with the match clock, and PvpService passes the ramped number per
		-- piece (`PvpConstants.specialChanceAt`), which wins over this field. So
		-- this is the fallback for a piece dealt outside a live match, not the
		-- number players meet.
		modifier = {
			turnSeconds = PvpConstants.PIECE_SECONDS,
			stormSeconds = PvpConstants.MATCH_SECONDS,
			blockTypeScale = 1,
			blockTypeChance = PvpConstants.SPECIAL_CHANCE_START,
			pvp = true,
		},
	},
} :: { Gamemode }

-- The modifier for a winning id. Anything unrecognised — including nil, which is
-- what a skipped vote hands back — plays the stage straight.
function Gamemodes.modifierFor(id: string?): Modifier
	if id == nil then
		return Gamemodes.DEFAULT
	end
	for _, mode in Gamemodes.List do
		if mode.id == id then
			return mode.modifier
		end
	end
	return Gamemodes.DEFAULT
end

return Gamemodes
