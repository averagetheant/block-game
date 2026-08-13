-- The two Robux buttons on the left rail. Registered here rather than in
-- TowerGame/Sidebar.luau because prompting a purchase is a client call, and a
-- shared Sidebar.luau would drag MarketplaceService onto the server.
--
-- They register into the rail's "actions" cluster, which is what puts them
-- below the Shop / Bag column with a gap — a one-shot purchase reads as a
-- different sort of thing from a window you open.
--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)
local Sidebar = require(ReplicatedStorage.Features.Sidebar)
local assets = require(ReplicatedStorage.Shared.Boil).assets

-- Client-realm sibling from another feature (StarterPlayerScripts.Features).
local StoreController = require(script.Parent.Parent.Store.StoreController)

if Constants.Presentations.actions then
	Sidebar.registerEntry({
		id = "TowerNuke",
		label = "Nuke",
		icon = assets.Icons.nuke,
		group = "actions",
		order = 1,
		onClick = function()
			StoreController.promptProduct(Constants.PRODUCTS.NUKE)
		end,
	})

	Sidebar.registerEntry({
		id = "TowerNextCheckpoint",
		label = "Skip",
		icon = assets.Icons.arrowRightOutline,
		group = "actions",
		order = 2,
		onClick = function()
			StoreController.promptProduct(Constants.PRODUCTS.NEXT_CHECKPOINT)
		end,
	})
end

return {}
