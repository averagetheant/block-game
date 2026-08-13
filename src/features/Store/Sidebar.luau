-- Store's entries on the left rail. Discovered by src/features/Sidebar/init.luau
-- at load time; see docs/game/Sidebar.md.
--
-- Declarative only — each entry names the UIShell frame it opens, and the
-- window's *contents* arrive separately from Store's *Presentation modules.
-- That's why this file works on both realms: there's nothing client-only in it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local assets = require(ReplicatedStorage.Shared.Boil).assets
local Constants = require(script.Parent.Constants)

return function(Sidebar)
	if Constants.Presentations.shop then
		Sidebar.registerEntry({
			id = "Shop",
			label = "Shop",
			icon = assets.Icons.shoppingBasket,
			frameId = Constants.SHOP_FRAME_ID,
			titleVariant = "yellow",
			order = 1,
		})
	end

	if Constants.Presentations.inventory then
		Sidebar.registerEntry({
			id = "Inventory",
			label = "Inventory",
			icon = assets.Icons.backpack,
			frameId = Constants.INVENTORY_FRAME_ID,
			windowTitle = "Inventory",
			titleVariant = "green",
			order = 2,
		})
	end
end
