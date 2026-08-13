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

Gamemodes.List = {
	-- Always the first panel on the ballot (order 0, and nothing else claims it).
	-- A vote whose options are all twists has no "leave it alone" answer, so the
	-- players can't decline a modifier — Classic is that answer, and putting it
	-- in a fixed position means it's the one panel you can pick without reading.
	{
		id = "classic",
		name = "Classic",
		blurb = "The game, played straight.",
		icon = assets.Icons.book,
		order = 0,
		-- Always on the ballot; the other slots are rolled from the twists. The
		-- players must always have a way to decline a modifier.
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
		order = 1,
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
		order = 2,
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
		order = 3,
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
		order = 4,
		-- The Stormy zone's hazard, everywhere. It keeps its ten-second warning,
		-- so this is a round-long pressure rather than an unfair one.
		modifier = {
			turnSeconds = Constants.TURN_SECONDS,
			stormSeconds = Constants.STORM_SECONDS,
			blockTypeScale = 1,
			alwaysLightning = true,
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
