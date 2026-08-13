-- What a block *does* when it lands, as opposed to what it looks like (that's
-- BlockSkins). Most blocks do nothing; the rest are the game's escalating
-- hazard, and they show up more often the further the tower has been pushed.
--
-- The odds curve lives here rather than in the service so the rate and the roll
-- can't drift apart:
--
--   chance = min(BASE_CHANCE + PER_CHECKPOINT * checkpoints, MAX_CHANCE)
--
-- Deliberately stingy at the bottom of the run: the first few floors are where
-- players are still learning to aim, and a hazard every other piece there reads
-- as noise rather than escalation. The curve only bites once a run is long.
--
-- `description` is the line the block's own name plate shows under its title
-- (see BlockLabel), so it's written for the player, not for this file.
--
-- `id` goes over the wire and is what a name plate looks up — append, don't
-- renumber.

export type Kind = "plain" | "explosion" | "glue" | "clone" | "bouncy" | "burning" | "noob"

export type BlockType = {
	id: number,
	kind: Kind,
	name: string,
	-- One short line, shown under the name on the block's plate.
	description: string,
	-- Tint used for the Highlight that marks the block, so a hazard reads at a
	-- glance without fighting whatever skin it rolled.
	tell: Color3,
	weight: number,
	-- True for types that bring their own model instead of a tetromino. Those
	-- skip the shape entirely: no cells, no skin dressing, no shape suffix on the
	-- name plate. TowerService hands the build off to the type's own module.
	overridesModel: boolean?,
}

local BlockTypes = {}

-- Odds that a piece is special at all.
BlockTypes.BASE_CHANCE = 0.03
BlockTypes.PER_CHECKPOINT = 0.035
BlockTypes.MAX_CHANCE = 0.4

BlockTypes.List = {
	{
		id = 1,
		kind = "explosion",
		name = "Bomb",
		description = "Explodes.",
		tell = Color3.fromRGB(255, 92, 72),
		weight = 3,
	},
	{
		id = 2,
		kind = "glue",
		name = "Glue",
		description = "Glues parts together.",
		tell = Color3.fromRGB(126, 240, 138),
		weight = 3,
	},
	{
		id = 3,
		kind = "clone",
		name = "Clone",
		description = "Duplicates itself.",
		tell = Color3.fromRGB(120, 214, 255),
		weight = 2,
	},
	{
		id = 4,
		kind = "bouncy",
		name = "Bouncy",
		description = "Bounces!",
		tell = Color3.fromRGB(255, 140, 230),
		weight = 3,
	},
	{
		id = 5,
		kind = "burning",
		name = "Burning",
		description = "Burns blocks, careful!",
		tell = Color3.fromRGB(255, 152, 48),
		weight = 2,
	},
	{
		id = 6,
		kind = "noob",
		name = "Noob",
		description = "Places a Noob.",
		tell = Color3.fromRGB(255, 214, 82),
		weight = 2,
		overridesModel = true,
	},
} :: { BlockType }

local byId: { [number]: BlockType } = {}
local totalWeight = 0
for _, blockType in BlockTypes.List do
	byId[blockType.id] = blockType
	totalWeight += blockType.weight
end

function BlockTypes.get(id: number): BlockType?
	return byId[id]
end

-- `scale` multiplies the odds before the cap — the hook a gamemode uses to make
-- a stage all hazards. 1 (the default) is the plain curve, and MAX_CHANCE still
-- applies however high it's scaled, so a stage can't be *only* special pieces.
function BlockTypes.chanceAt(checkpoints: number, scale: number?): number
	local chance = (BlockTypes.BASE_CHANCE + BlockTypes.PER_CHECKPOINT * checkpoints) * (scale or 1)
	return math.min(chance, BlockTypes.MAX_CHANCE)
end

-- nil for an ordinary block. `checkpoints` drives how often that isn't the case.
function BlockTypes.roll(checkpoints: number, scale: number?): BlockType?
	if math.random() > BlockTypes.chanceAt(checkpoints, scale) then
		return nil
	end

	local roll = math.random() * totalWeight
	for _, blockType in BlockTypes.List do
		roll -= blockType.weight
		if roll <= 0 then
			return blockType
		end
	end
	return BlockTypes.List[1]
end

return BlockTypes
