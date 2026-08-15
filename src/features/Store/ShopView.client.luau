-- Wires the pure ShopUI to live data: ownership + balances off the PlayerData
-- replica, and the Catalog's Changed signal so a late registration shows up
-- without a remount.
--
-- Balances are read per currency rather than as one blob, because each one
-- lives wherever its owning feature keeps it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

local Boil = require(ReplicatedStorage.Shared.Boil)
local Catalog = require(ReplicatedStorage.Features.Store.Catalog)
local Constants = require(ReplicatedStorage.Features.Store.Constants)
local ShopUI = require(ReplicatedStorage.Features.Store.ShopUI)

-- Client-realm siblings (StarterPlayerScripts.Features tree).
local StoreController = require(script.Parent.StoreController)
local PlayerDataController = require(script.Parent.Parent.PlayerData.PlayerDataController)
local AnalyticsController = require(script.Parent.Parent.Analytics.AnalyticsController)

-- Re-render when the catalog changes. Registration happens at load, so in
-- practice this only fires for a feature that registers late — cheap insurance
-- against a shop that renders once and then lies.
local function useCatalogVersion()
	local _, setVersion = React.useState(0)
	React.useEffect(function()
		local conn = Catalog.Changed:Connect(function()
			setVersion(function(v: number): number
				return v + 1
			end)
		end)
		return function()
			conn:Disconnect()
		end
	end, {})
end

-- Gamepass ownership isn't replica state — it's Roblox's answer, and it lands a
-- moment after join and again when a purchase prompt closes. Same shape as the
-- catalog subscription above, for the same reason: a shop that read once at
-- mount would sit on "Buy" for a pass the player already has.
local function useGamepassVersion()
	local _, setVersion = React.useState(0)
	React.useEffect(function()
		local conn = StoreController.GamepassesChanged:Connect(function()
			setVersion(function(v: number): number
				return v + 1
			end)
		end)
		return function()
			conn:Disconnect()
		end
	end, {})
end

-- Opening the shop starts three funnels at once, because all three of them
-- begin with the same event: the player is now looking at the cards. The
-- Frame this renders inside unmounts its children on close (see
-- UIShell/Frame.ui.luau), so an empty dependency list here is exactly
-- once per open — not once per session, and not once per render.
local function useShopOpened()
	React.useEffect(function()
		AnalyticsController.start("shop", "Shop Opened")
		AnalyticsController.start("product", "Product Shown")
		AnalyticsController.start("gamepass", "Gamepass Shown")
		AnalyticsController.onboarding(5)
	end, {})
end

return function()
	useCatalogVersion()
	useGamepassVersion()
	useShopOpened()

	-- Subscribing to the whole profile rather than one key: a purchase moves
	-- both the Store slice and whichever feature's slice holds the currency.
	Boil.useReplica(PlayerDataController)

	local store = Boil.useReplica(PlayerDataController, Constants.PROFILE_KEY) or {}
	local owned = store.Owned or {}

	local balances: { [string]: number } = {}
	for _, currency in Catalog.listCurrencies() do
		balances[currency.id] = StoreController.balance(currency.id)
	end

	local ownedGamepasses: { [number]: boolean } = {}
	for _, pass in Catalog.listGamepasses() do
		ownedGamepasses[pass.id] = StoreController.ownsGamepass(pass.id)
	end

	return React.createElement(ShopUI, {
		owned = owned,
		ownedGamepasses = ownedGamepasses,
		balances = balances,
		onBuyPack = StoreController.purchase,
		onBuyProduct = StoreController.promptProduct,
		onBuyGamepass = StoreController.promptGamepass,
		onTabViewed = function()
			-- Which tab isn't recorded, only that they moved off the first one.
			-- The step is "they went looking", and a per-tab breakdown would
			-- need a custom field per kind — cardinality the dashboard charges
			-- for and nothing here would read.
			AnalyticsController.step("shop", "Tab Viewed")
		end,
	})
end
