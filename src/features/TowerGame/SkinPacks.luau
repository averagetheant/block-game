--!strict
-- Buyable block looks. One entry here becomes one card in the shop's Skins tab
-- and one equippable pack in the inventory — Store.luau reads this list, and so
-- does TowerService, so the price and the material can't drift apart.
--
-- A skin pack overrides the look of the blocks its owner drops, and it overrides
-- whatever the current zone would have dressed them in. That's the whole
-- product: Retro turns the tower into grey studded bricks, and the neon blocks
-- in it stay neon.
--
-- There are three ways a pack can do that, and a pack picks one: `material`
-- swaps the surface (Neon), `hue` tints the block (the ten colours), and
-- `blockSkin` pins the rolled BlockSkin outright (Needoh) — surface, sounds and
-- all, which is the only one of the three a player can *hear*.
--
-- It's a server override on the block, not a local one on the viewer. The pack
-- is read once when the turn begins and carried on the piece for life, so a
-- bought skin is something the whole room sees on *your* blocks — not something
-- that repaints everyone else's tower on your screen.
--
-- `id` is a Store pack id and is persisted on the profile: append, don't rename.

export type SkinPack = {
	id: string,
	name: string,
	description: string,
	icon: string?,
	price: number,
	currency: string,
	variant: string?,
	order: number?,
	-- What every block part becomes while this pack is equipped. nil leaves the
	-- rolled BlockSkin's material alone, which is what the colour packs want —
	-- they're about hue, not surface.
	material: Enum.Material?,
	-- Pins the BlockSkin every block rolls, by `BlockSkins.Skin.id`. Where
	-- `material` overrides one property of whatever rolled, this replaces the
	-- roll outright — surface, transparency *and* sounds — so a Needoh pack is
	-- a tower that squishes on every landing, not one that merely looks glassy.
	blockSkin: number?,
	-- Base hue for a colour pack, in HSV. Each block rolls its own *shade* of it
	-- (see `SkinPacks.colorFor`), so a tower built in one pack is a run of
	-- related colours rather than a wall of one flat value.
	hue: number?,
	-- How far the roll may wander from the base, per channel. A pack that wants
	-- a tight family (Black, White) sets these low; the bright colours can
	-- afford a wide spread because the hue still reads.
	saturation: number?,
	saturationJitter: number?,
	value: number?,
	valueJitter: number?,
	-- Passed through to the Store card. False keeps the pack out of the shop
	-- entirely — it exists to be granted (see DailyRewards.luau) and `price` is
	-- only what it *would* cost if it ever went on sale.
	forSale: boolean?,
}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local assets = require(ReplicatedStorage.Shared.Boil).assets
local BlockSkins = require(script.Parent.BlockSkins)
local Constants = require(script.Parent.Constants)

-- The BlockSkin the Needoh pack pins. Named rather than written as `2` at the
-- point of use so the pack and the skin can't drift apart silently — if the
-- skin is ever renumbered this stops resolving in one obvious place.
local NEEDOH_SKIN_ID = 2

local SkinPacks = {}

-- The Store pack kind these register under.
SkinPacks.KIND = "skin"

-- One entry for each of the ten colours. Written as a table rather than ten
-- literals because every one of them differs only in name, hue and price band —
-- spelling them out would be ten near-identical blocks to keep in sync.
--
-- `hue` is the HSV hue (0–1). The greys carry a hue anyway; it's unused at zero
-- saturation but keeps every row the same shape.
local COLORS = {
	{ id = "red", name = "Red", hue = 0.00, variant = "red" },
	{ id = "orange", name = "Orange", hue = 0.07, variant = "yellow" },
	{ id = "yellow", name = "Yellow", hue = 0.14, variant = "yellow" },
	{ id = "green", name = "Green", hue = 0.30, variant = "green" },
	{ id = "blue", name = "Blue", hue = 0.58, variant = "blue" },
	{ id = "purple", name = "Purple", hue = 0.76, variant = "purple" },
	{ id = "pink", name = "Pink", hue = 0.90, variant = "red" },
	-- The three neutrals. Near-zero saturation, so the variation is entirely in
	-- brightness — which is exactly what "shades of grey" means.
	{ id = "white", name = "White", hue = 0, saturation = 0.02, saturationJitter = 0.02, value = 0.96, valueJitter = 0.06, variant = "white" },
	{ id = "grey", name = "Grey", hue = 0, saturation = 0.03, saturationJitter = 0.03, value = 0.55, valueJitter = 0.22, variant = "white" },
	{ id = "black", name = "Black", hue = 0, saturation = 0.05, saturationJitter = 0.05, value = 0.16, valueJitter = 0.1, variant = "purple" },
}

SkinPacks.List = {
	{
		id = "skins.needoh",
		name = "Needoh Blocks",
		description = "Every block is a Needoh — glassy, squishy, and it squeaks on every landing.",
		icon = assets.Icons.wheel,
		price = Constants.NEEDOH_SKIN_PRICE,
		currency = Constants.CURRENCY_ID,
		variant = "red",
		order = 1,
		blockSkin = NEEDOH_SKIN_ID,
		-- Earned, never bought: it's the last day of the daily run, and a grand
		-- prize you could have bought on day one isn't one.
		forSale = false,
	},
	{
		id = "skins.neon",
		name = "Neon Blocks",
		description = "Every block glows. Overrides zone materials — a Retro zone can't dull it.",
		icon = assets.Icons.rocket,
		price = 100,
		currency = Constants.CURRENCY_ID,
		variant = "blue",
		order = 2,
		material = Enum.Material.Neon,
	},
	{
		id = "skins.gold",
		name = "Golden Blocks",
		description = "Polished gold, every piece. Earned by clearing your first checkpoint — it's never for sale.",
		icon = assets.Icons.bandOfCash,
		-- Inert while `forSale` is false. Kept at the colour-pack price only so the
		-- row reads like the rest, and so there's a number if it ever goes on sale.
		price = Constants.COLOR_SKIN_PRICE,
		currency = Constants.CURRENCY_ID,
		variant = "yellow",
		order = 3,
		-- The one pack that sets *both* halves. Foil is what makes it read as metal
		-- rather than as another yellow — the hue alone would land it next to the
		-- sixty-coin Yellow pack, which is exactly what a reward for surviving the
		-- game's steepest drop-off must not do.
		material = Enum.Material.Foil,
		hue = 0.12,
		-- A tight family: gold that wanders is brass on one block and lemon on the
		-- next, and the tower stops reading as one metal.
		saturation = 0.72,
		saturationJitter = 0.1,
		value = 0.94,
		valueJitter = 0.08,
		-- Earned, never bought — the first-checkpoint quest is the only way in.
		-- See Constants.FIRST_CHECKPOINT_PACK, which is the id this row answers to.
		forSale = false,
	},
} :: { SkinPack }

-- The packs written out above. Counted rather than hardcoded so the colours
-- keep sorting after them however many get added.
local NAMED_PACKS = #SkinPacks.List

for index, color in COLORS do
	table.insert(SkinPacks.List, {
		id = `skins.{color.id}`,
		name = `{color.name} Blocks`,
		description = `Every block you place is a shade of {string.lower(color.name)}.`,
		icon = assets.Icons.rebirth,
		price = Constants.COLOR_SKIN_PRICE,
		currency = Constants.CURRENCY_ID,
		variant = color.variant,
		-- After the named packs, in the order they're listed above.
		order = index + NAMED_PACKS,
		hue = color.hue,
		saturation = color.saturation,
		saturationJitter = color.saturationJitter,
		value = color.value,
		valueJitter = color.valueJitter,
	})
end

local byId: { [string]: SkinPack } = {}
for _, pack in SkinPacks.List do
	byId[pack.id] = pack
end

function SkinPacks.get(id: string?): SkinPack?
	if id == nil then
		return nil
	end
	return byId[id]
end

-- The BlockSkin this pack pins, if it pins one. nil means "whatever the block
-- rolled", which is every pack but Needoh.
function SkinPacks.blockSkinFor(pack: SkinPack?): BlockSkins.Skin?
	if pack == nil or pack.blockSkin == nil then
		return nil
	end
	return BlockSkins.get(pack.blockSkin)
end

-- Whether this pack decides what the block's surface is. True for a material
-- pack (Neon) and for one that pins a skin (Needoh) — both of them are selling
-- a surface, so a Retro zone doesn't get to stud it over. False for the colour
-- packs, which own the hue and leave the surface to the zone.
function SkinPacks.ownsSurface(pack: SkinPack?): boolean
	if pack == nil then
		return false
	end
	return pack.material ~= nil or pack.blockSkin ~= nil
end

-- A block's colour under this pack, rolled fresh per block.
--
-- The point of rolling is that a flat fill looks like a bug: forty identical
-- blocks read as one solid mass with no edges, and the tower stops being legible
-- as a stack of pieces. Varying the shade keeps every block's boundary visible
-- while still reading as "this player builds in red".
--
-- Returns nil for a pack that isn't a colour pack (Neon), whose blocks keep the
-- random colour the game already gives them.
function SkinPacks.colorFor(pack: SkinPack?): Color3?
	if pack == nil or pack.hue == nil then
		return nil
	end

	local saturation = pack.saturation or Constants.COLOR_SKIN_SATURATION
	local satJitter = pack.saturationJitter or Constants.COLOR_SKIN_SATURATION_JITTER
	local value = pack.value or Constants.COLOR_SKIN_VALUE
	local valJitter = pack.valueJitter or Constants.COLOR_SKIN_VALUE_JITTER

	-- Hue wanders too, but far less than the other two: past a narrow band a
	-- "red" pack starts handing out oranges and the pack stops being what it
	-- says on the card.
	local hue = (pack.hue + (math.random() * 2 - 1) * Constants.COLOR_SKIN_HUE_JITTER) % 1
	return Color3.fromHSV(
		hue,
		math.clamp(saturation + (math.random() * 2 - 1) * satJitter, 0, 1),
		math.clamp(value + (math.random() * 2 - 1) * valJitter, 0, 1)
	)
end

return SkinPacks
