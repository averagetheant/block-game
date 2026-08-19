-- TowerGame's entries in the Store catalog. Discovered by
-- src/features/Store/init.luau at load time; see docs/game/Store.md.
--
-- Four separate things get registered here, and they're separate on purpose:
--
--   * the "coins" currency — TowerGame earns it (CashService) and keeps it in
--     its own profile slice, so Store is told *where* the balance lives rather
--     than being given a copy of it;
--   * the skin packs, read out of SkinPacks so the shop card and the client
--     override can't disagree about the price;
--   * the developer products — the three cash bundles, which StoreService
--     grants generically, and the two action products, whose effects are
--     registered separately by TowerProductsService (a handler is server code
--     and this file loads on both realms);
--   * the gamepasses, which are cards only for the same reason — what 2x Cash
--     and Double Turn *do* lives in CashService and TowerService, both of which
--     ask StoreService whether the player owns the pass.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local assets = require(ReplicatedStorage.Shared.Boil).assets
local Constants = require(script.Parent.Constants)
local SkinPacks = require(script.Parent.SkinPacks)

local CASH_ICON = Constants.CASH_IMAGE
local PRODUCTS = Constants.PRODUCTS
local GAMEPASSES = Constants.GAMEPASSES

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
			-- Needoh Blocks is the daily run's grand prize and nothing else, so
			-- it's registered (grantable, ownable, equippable) but never carded.
			forSale = pack.forSale,
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

	-- The two gamepasses. A card is all that's registered here — the effects are
	-- server code (CashService multiplies its payouts, TowerService hands out the
	-- second turn), and this file loads on both realms.
	Store.registerGamepass({
		id = GAMEPASSES.DOUBLE_CASH,
		name = "2x Cash",
		-- Kept short on purpose: the card gives a description four wrapped lines
		-- before it clips (Store.Constants.CARD_HEIGHT).
		description = `Every coin you earn counts {Constants.DOUBLE_CASH_MULTIPLIER}x — height, zones, and the clock.`,
		icon = CASH_ICON,
		variant = "green",
		order = 1,
	})
	Store.registerGamepass({
		id = GAMEPASSES.DOUBLE_TURN,
		name = "Double Turn",
		description = `Take {Constants.DOUBLE_TURN_TURNS} pieces in a row every time the queue comes round to you.`,
		icon = assets.Icons.rebirth,
		variant = "purple",
		order = 2,
	})

	if not Constants.Presentations.actions then
		return
	end

	-- The action buttons. Registered as "action" products so they never show up
	-- as shop cards — their button is the sidebar entry, or in Extend Storm's
	-- case the one on the HUD beside the clock it buys.
	Store.registerProduct({
		id = PRODUCTS.NUKE,
		name = "Nuke",
		description = "Blow the standing tower off the plane — or, in a PVP match, every tower but your own. The run keeps going; the climb doesn't.",
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

	Store.registerProduct({
		id = PRODUCTS.EXTEND_STORM,
		name = "Extend Storm",
		description = `Put {Constants.EXTEND_STORM_SECONDS} seconds back on the stage clock, for the whole room.`,
		icon = CASH_ICON,
		group = "action",
		order = 3,
	})
end
