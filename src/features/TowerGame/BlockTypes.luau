-- What a block *does* when it lands, as opposed to what it looks like (that's
-- BlockSkins). Most blocks do nothing; the rest are the game's escalating
-- hazard, and they show up more often the further the tower has been pushed.
--
-- The odds curve lives here rather than in the service so the rate and the roll
-- can't drift apart:
--
--   chance = min(BASE_CHANCE + PER_CHECKPOINT * checkpoints, MAX_CHANCE)
--
-- At checkpoint 0 that's a rare surprise; by the fifth floor it's most of a
-- coin flip, which is what turns a calm stack into a scramble.

export type Kind = "plain" | "explosion" | "glue"

export type BlockType = {
	id: number,
	kind: Kind,
	name: string,
	-- Tint used for the Highlight that marks the block, so a hazard reads at a
	-- glance without fighting whatever skin it rolled.
	tell: Color3,
	weight: number,
}

local BlockTypes = {}

-- Odds that a piece is special at all.
BlockTypes.BASE_CHANCE = 0.08
BlockTypes.PER_CHECKPOINT = 0.06
BlockTypes.MAX_CHANCE = 0.45

BlockTypes.List = {
	{
		id = 1,
		kind = "explosion",
		name = "Explosive",
		tell = Color3.fromRGB(255, 92, 72),
		weight = 1,
	},
	{
		id = 2,
		kind = "glue",
		name = "Glue",
		tell = Color3.fromRGB(126, 240, 138),
		weight = 1,
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

function BlockTypes.chanceAt(checkpoints: number): number
	return math.min(BlockTypes.BASE_CHANCE + BlockTypes.PER_CHECKPOINT * checkpoints, BlockTypes.MAX_CHANCE)
end

-- nil for an ordinary block. `checkpoints` drives how often that isn't the case.
function BlockTypes.roll(checkpoints: number): BlockType?
	if math.random() > BlockTypes.chanceAt(checkpoints) then
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
