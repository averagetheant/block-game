--!nonstrict
-- UI Labs story for the shop body, mounted inside a real Window so the tabs and
-- grids are seen at the width they actually get.
--
-- Requiring Features.Store (not just the submodules) is what runs the catalog's
-- auto-discovery, so this story shows whatever the installed features actually
-- registered rather than a mock. Ownership and balances are the controls —
-- those come from a replica in game, which UI Labs doesn't have.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Features = ReplicatedStorage:WaitForChild("Features")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local UILabs = require(ReplicatedStorage.Packages.UILabs)
local ui = require(ReplicatedStorage.Shared.Boil).ui

local Store = require(Features:WaitForChild("Store"))

return {
	summary = "Shop window: one tab per registered pack kind plus a Robux tab (currency bundles above gamepasses). Slide `balance` up to see the Buy buttons come alive; tick `ownEverything` to see the Owned state.",
	react = React,
	reactRoblox = ReactRoblox,

	controls = {
		balance = UILabs.Slider(0, 0, 1000, 10),
		ownEverything = false,
	},

	story = function(props)
		local c = props.controls

		-- Every registered currency gets the same slider value; the shop reads
		-- balances per currency and there's only one in the base game.
		local balances = {}
		for _, currency in Store.Catalog.listCurrencies() do
			balances[currency.id] = c.balance
		end

		local owned = {}
		if c.ownEverything then
			for _, pack in Store.Catalog.listPacks() do
				owned[pack.id] = true
			end
		end

		return React.createElement(ui.Window, {
			title = "Shop",
			icon = ui.assets.Icons.shoppingBasket,
			titleVariant = "yellow",
			size = UDim2.fromOffset(820, 600),
		}, {
			Content = React.createElement(Store.ShopUI, {
				owned = owned,
				balances = balances,
				onBuyPack = function(id)
					print(`[Store] buy pack {id}`)
				end,
				onBuyProduct = function(id)
					print(`[Store] prompt product {id}`)
				end,
				onBuyGamepass = function(id)
					print(`[Store] prompt gamepass {id}`)
				end,
			}),
		})
	end,
}
