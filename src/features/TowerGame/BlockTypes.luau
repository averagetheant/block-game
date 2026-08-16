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

export type Kind =
	"plain"
	| "explosion"
	| "glue"
	| "clone"
	| "bouncy"
	| "burning"
	| "noob"
	| "anvil"
	| "ice"
	| "anchor"
	| "mystery"
	| "crate"
	| "feather"
	| "ghost"
	| "magnet"

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
	-- True for types a Mystery block may turn into. Only types whose effect still
	-- means something *after* a landing qualify: a Mystery that revealed itself as
	-- Anvil would have already fallen at ordinary weight, so the reveal would be a
	-- word with no event behind it. See `rollMystery`.
	viaMystery: boolean?,
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
		viaMystery = true,
	},
	{
		id = 2,
		kind = "glue",
		name = "Glue",
		description = "Glues parts together.",
		tell = Color3.fromRGB(126, 240, 138),
		weight = 3,
		viaMystery = true,
	},
	{
		id = 3,
		kind = "clone",
		name = "Clone",
		description = "Duplicates itself.",
		tell = Color3.fromRGB(120, 214, 255),
		weight = 2,
		viaMystery = true,
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
		viaMystery = true,
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
	-- Anvil / Ice / Feather are the *physics* types: each changes one number in
	-- the block's own PhysicalProperties (or, for Feather, how fast it may fall)
	-- and has nothing to resolve on landing. What they do is felt on the way down
	-- and for the rest of the run, which is why none of them is in the Mystery
	-- pool — a reveal has to be an event.
	{
		id = 7,
		kind = "anvil",
		name = "Anvil",
		description = "Heavy!",
		tell = Color3.fromRGB(128, 136, 152),
		weight = 3,
	},
	{
		id = 8,
		kind = "ice",
		name = "Ice",
		description = "Nothing sticks.",
		tell = Color3.fromRGB(196, 244, 255),
		weight = 3,
	},
	{
		id = 9,
		kind = "anchor",
		name = "Anchor",
		description = "Locks itself in place.",
		tell = Color3.fromRGB(86, 104, 200),
		weight = 2,
		viaMystery = true,
	},
	-- Not in its own pool, for the obvious reason.
	{
		id = 10,
		kind = "mystery",
		name = "Mystery",
		description = "???",
		tell = Color3.fromRGB(196, 118, 255),
		weight = 2,
	},
	{
		id = 11,
		kind = "crate",
		name = "Crate",
		description = "Breaks apart!",
		tell = Color3.fromRGB(190, 140, 84),
		weight = 3,
		viaMystery = true,
	},
	{
		id = 12,
		kind = "feather",
		name = "Feather",
		description = "Takes its time.",
		tell = Color3.fromRGB(255, 240, 200),
		weight = 2,
	},
	-- Ghost belongs with the physics types rather than the landing ones, and for
	-- their reason: what it does happens on the way down. It's out of the Mystery
	-- pool because a Ghost revealed after settling would have fallen solid — the
	-- reveal would name a thing that had already not happened.
	{
		id = 13,
		kind = "ghost",
		name = "Ghost",
		description = "Falls through the tower.",
		tell = Color3.fromRGB(214, 208, 255),
		weight = 2,
	},
	{
		id = 14,
		kind = "magnet",
		name = "Magnet",
		description = "Pulls blocks in.",
		tell = Color3.fromRGB(208, 72, 96),
		weight = 2,
		viaMystery = true,
	},
} :: { BlockType }

local byId: { [number]: BlockType } = {}
local totalWeight = 0
-- What a Mystery block may turn into, and the weight to roll it against. Built
-- from the same `weight` the ordinary roll uses, so a type that's rare as a
-- piece stays rare as a reveal.
local mysteryPool: { BlockType } = {}
local mysteryWeight = 0
for _, blockType in BlockTypes.List do
	byId[blockType.id] = blockType
	totalWeight += blockType.weight
	if blockType.viaMystery then
		table.insert(mysteryPool, blockType)
		mysteryWeight += blockType.weight
	end
end

function BlockTypes.get(id: number): BlockType?
	return byId[id]
end

-- What a Mystery block turns out to have been, rolled the moment it comes to
-- rest. nil when nothing is eligible — with an empty pool the block simply
-- stays a dud, which is a duller outcome than a reveal but not a broken one.
function BlockTypes.rollMystery(): BlockType?
	if #mysteryPool == 0 then
		return nil
	end
	local roll = math.random() * mysteryWeight
	for _, blockType in mysteryPool do
		roll -= blockType.weight
		if roll <= 0 then
			return blockType
		end
	end
	return mysteryPool[#mysteryPool]
end

-- `scale` multiplies the odds before the cap — the hook a gamemode uses to make
-- a stage all hazards. 1 (the default) is the plain curve, and MAX_CHANCE still
-- applies however high it's scaled, so a stage can't be *only* special pieces.
function BlockTypes.chanceAt(checkpoints: number, scale: number?): number
	local chance = (BlockTypes.BASE_CHANCE + BlockTypes.PER_CHECKPOINT * checkpoints) * (scale or 1)
	return math.min(chance, BlockTypes.MAX_CHANCE)
end

-- nil for an ordinary block. `checkpoints` drives how often that isn't the case.
-- `override` is a flat chance that replaces the curve *and* its cap, for a
-- gamemode that wants to promise a number rather than scale one. Scaling can't
-- make that promise: MAX_CHANCE holds the result at 0.4 however high the scale
-- goes, so a mode advertising "70% special" would quietly deliver 40%.
function BlockTypes.roll(checkpoints: number, scale: number?, override: number?): BlockType?
	local chance = if override ~= nil then override else BlockTypes.chanceAt(checkpoints, scale)
	if math.random() > chance then
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
