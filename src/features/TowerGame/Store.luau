-- TowerGame's entries in the Store catalog. Discovered by
-- src/features/Store/init.luau at load time; see docs/game/Store.md.
--
-- Three separate things get registered here, and they're separate on purpose:
--
--   * the "coins" currency — TowerGame earns it (CashService) and keeps it in
--     its own profile slice, so Store is told *where* the balance lives rather
--     than being given a copy of it;
--   * the skin packs, read out of SkinPacks so the shop card and the client
--     override can't disagree about the price;
--   * the developer products — the three cash bundles, which StoreService
--     grants generically, and the two action products, whose effects are
--     registered separately by TowerProductsService (a handler is server code
--     and this file loads on both realms).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local assets = require(ReplicatedStorage.Shared.Boil).assets
local Constants = require(script.Parent.Constants)
local SkinPacks = require(script.Parent.SkinPacks)

local CASH_ICON = Constants.CASH_IMAGE
local PRODUCTS = Constants.PRODUCTS

return function(Store)
	Store.registerCurrency({
		id = Constants.CURRENCY_ID,
		name = "Coins",
		icon = CASH_ICON,
		path = { Constants.PROFILE_KEY, "Cash" },
	})

	Store.registerKind({
		id = SkinPacks.KIND,
		title = "Skins",
		order = 1,
	})

	for _, pack in SkinPacks.List do
		Store.registerPack({
			id = pack.id,
			kind = SkinPacks.KIND,
			name = pack.name,
			description = pack.description,
			icon = pack.icon,
			price = pack.price,
			currency = pack.currency,
			variant = pack.variant,
			order = pack.order,
		})
	end

	-- Coins for Robux. Roblox's own prompt shows the price, so the card only
	-- has to say what you get.
	local bundles = {
		{ id = PRODUCTS.CASH_500, amount = 500, variant = "green", order = 1 },
		{ id = PRODUCTS.CASH_1000, amount = 1000, variant = "blue", order = 2 },
		{ id = PRODUCTS.CASH_10000, amount = 10000, variant = "purple", order = 3 },
	}
	for _, bundle in bundles do
		Store.registerProduct({
			id = bundle.id,
			name = `{bundle.amount} Coins`,
			description = `Adds {bundle.amount} coins to your balance.`,
			icon = CASH_ICON,
			group = "currency",
			currency = Constants.CURRENCY_ID,
			amount = bundle.amount,
			variant = bundle.variant,
			order = bundle.order,
		})
	end

	-- A placeholder until real gamepasses are configured on the place. Id 0 is
	-- what makes the button decline politely instead of erroring — see
	-- StoreController.promptGamepass.
	Store.registerGamepass({
		id = 0,
		name = "Coming Soon",
		description = "A gamepass will live here. Set its id on this registration to switch it on.",
		icon = assets.Icons.questionMark,
		variant = "yellow",
		order = 1,
	})

	if not Constants.Presentations.actions then
		return
	end

	-- The two rail buttons. Registered as "action" products so they never show
	-- up as shop cards — their button is the sidebar entry.
	Store.registerProduct({
		id = PRODUCTS.NUKE,
		name = "Nuke",
		description = "Throw the whole tower off the plane and start the run over.",
		icon = CASH_ICON,
		group = "action",
		order = 1,
	})
	Store.registerProduct({
		id = PRODUCTS.NEXT_CHECKPOINT,
		name = "Next Checkpoint",
		description = "Clear the current stage from wherever the tower is.",
		icon = CASH_ICON,
		group = "action",
		order = 2,
	})
end
