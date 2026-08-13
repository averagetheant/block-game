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

	Store.registerPack({
		id = Catalog.PACK_ID,
		kind = "reaction",
		name = "Emoji Pack",
		description = "Four more reactions to swap into your bar, including one image reaction.",
		icon = assets.Icons.friends,
		price = 100,
		currency = "coins",
		variant = "purple",
		order = 1,
	})

	-- Registered but unused if the bar is switched off — the pack would still
	-- be buyable and there'd be nowhere to put it, so keep the two in step.
	if not Constants.Presentations.bar then
		warn("[Reactions] the reaction bar is off, but the Emoji Pack is still for sale")
	end
end
