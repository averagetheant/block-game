-- Wires the pure InventoryUI to live data: what's owned and what's equipped,
-- both off the Store slice of the PlayerData replica.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

local Boil = require(ReplicatedStorage.Shared.Boil)
local Catalog = require(ReplicatedStorage.Features.Store.Catalog)
local Constants = require(ReplicatedStorage.Features.Store.Constants)
local InventoryUI = require(ReplicatedStorage.Features.Store.InventoryUI)

-- Client-realm siblings (StarterPlayerScripts.Features tree).
local StoreController = require(script.Parent.StoreController)
local PlayerDataController = require(script.Parent.Parent.PlayerData.PlayerDataController)
local AnalyticsController = require(script.Parent.Parent.Analytics.AnalyticsController)

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

-- One session per visit to the window. The Frame unmounts its children on
-- close, so this runs exactly once per open.
local function useInventoryOpened()
	React.useEffect(function()
		AnalyticsController.start("inventory", "Inventory Opened")
	end, {})
end

return function()
	useCatalogVersion()
	useInventoryOpened()

	local store = Boil.useReplica(PlayerDataController, Constants.PROFILE_KEY) or {}

	return React.createElement(InventoryUI, {
		owned = store.Owned or {},
		equipped = store.Equipped or {},
		onEquip = StoreController.equip,
		onUnequip = StoreController.unequip,
		onTabViewed = function()
			AnalyticsController.step("inventory", "Tab Viewed")
		end,
	})
end
