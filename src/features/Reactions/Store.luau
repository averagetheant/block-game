-- Reactions' entries in the Store catalog. Discovered by
-- src/features/Store/init.luau at load time; see docs/game/Store.md.
--
-- The pack is priced in "coins", a currency this feature doesn't own or know
-- how to pay out — TowerGame registers it. If TowerGame were uninstalled the
-- pack would simply never be affordable, which is the right failure: a shop
-- that can't be bought from beats a shop that crashes.
--
-- `inventory = false` on the kind because Reactions ships its own Inventory
-- tab: equipping a reaction means putting it in a bar slot, not selecting one
-- pack, and the Store's generic "equip one pack" grid can't express that.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Catalog = require(script.Parent.Catalog)
local Constants = require(script.Parent.Constants)
local assets = require(ReplicatedStorage.Shared.Boil).assets

return function(Store)
	Store.registerKind({
		id = "reaction",
		title = "Reactions",
		order = 2,
		inventory = false,
	})

	-- Every pack is the same shape, so they're declared as data rather than as
	-- four near-identical registerPack calls. The cards draw their *contents*
	-- (see ReactionsPresentation), so the icon here is only a fallback for a
	-- client that somehow has no preview registered.
	local packs = {
		{
			id = Catalog.PACK_ID,
			name = "Emoji Pack",
			description = "Four more reactions, including one image reaction.",
			price = 100,
			variant = "purple",
		},
		{
			id = Catalog.HYPE_PACK_ID,
			name = "Hype Pack",
			description = "For when the tower is actually going well.",
			price = 100,
			variant = "yellow",
		},
		{
			id = Catalog.SALT_PACK_ID,
			name = "Salt Pack",
			description = "For when it is not.",
			price = 100,
			variant = "blue",
		},
		{
			id = Catalog.BRAINROT_PACK_ID,
			name = "Brainrot Pack",
			description = "Four image reactions. You know the ones.",
			price = 150,
			variant = "green",
		},
	}

	for index, pack in packs do
		Store.registerPack({
			id = pack.id,
			kind = "reaction",
			name = pack.name,
			description = pack.description,
			icon = assets.Icons.friends,
			price = pack.price,
			currency = "coins",
			variant = pack.variant,
			order = index,
		})
	end

	-- Registered but unused if the bar is switched off — the pack would still
	-- be buyable and there'd be nowhere to put it, so keep the two in step.
	if not Constants.Presentations.bar then
		warn("[Reactions] the reaction bar is off, but the Emoji Pack is still for sale")
	end
end
