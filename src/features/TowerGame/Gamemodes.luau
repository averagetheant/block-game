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
-- one place to look to know how a stage will play and no compounding across
-- stages. `DEFAULT` is the un-voted stage — what the game did before any of
-- this existed, and what it falls back to when there's no vote (server start,
-- an aborted poll, a fresh run).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)

export type Modifier = {
	-- Seconds on a turn clock before the piece drops itself.
	turnSeconds: number,
	-- Seconds on the stage clock before the storm takes the tower.
	stormSeconds: number,
	-- Multiplier on the odds a piece is a special type (bomb / burning / Noob).
	-- 1 is the normal curve; the roll is still clamped by BlockTypes.MAX_CHANCE.
	blockTypeScale: number,
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
	{
		id = "towerRush",
		name = "Tower Rush",
		blurb = "Beat a faster storm.",
		icon = "rbxassetid://137349421699691",
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
		icon = "rbxassetid://92211074359779",
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
		id = "mystery",
		name = "Mystery Mode",
		blurb = "Bombs. Lots of bombs.",
		icon = "rbxassetid://120234519496461",
		order = 3,
		-- Special pieces go from a garnish to the point of the stage. Still
		-- capped by BlockTypes.MAX_CHANCE, so it's "most pieces", not "all".
		modifier = {
			turnSeconds = Constants.TURN_SECONDS,
			stormSeconds = Constants.STORM_SECONDS,
			blockTypeScale = 6,
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
