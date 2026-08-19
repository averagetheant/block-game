-- The Robux buttons on the left rail. Registered here rather than in
-- TowerGame/Sidebar.luau because prompting a purchase is a client call, and a
-- shared Sidebar.luau would drag MarketplaceService onto the server.
--
-- They register into the rail's "actions" cluster, which is what puts them
-- below the Shop / Bag column with a gap — a one-shot purchase reads as a
-- different sort of thing from a window you open.
--
-- **Two of the three are mode-specific**, because two of them mean something
-- different — or nothing at all — depending on which mode owns the board:
--
--   classic   Nuke (the one shared tower)   Skip (the current stage)
--   PVP       Nuke Others (every lane but yours)
--
-- Nuke and Nuke Others are the *same product*: same id, same price, same
-- receipt. What changes is the label, because what you get for your Robux
-- changes with the board — see `PvpService.nukeOthers`. They're two entries
-- rather than one with a swapping label so the rail stays what it is, a list of
-- static declarations, and each one can say plainly when it applies. Skip has no
-- PVP twin at all: a match has no checkpoints, so there is nothing to skip.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)
local Sidebar = require(ReplicatedStorage.Features.Sidebar)
local assets = require(ReplicatedStorage.Shared.Boil).assets

-- Client-realm siblings. StoreController is another feature's
-- (StarterPlayerScripts.Features.Store); PvpController is this one's.
local StoreController = require(script.Parent.Parent.Store.StoreController)
local PvpController = require(script.Parent.PvpController)

if Constants.Presentations.actions then
	Sidebar.registerEntry({
		id = "TowerNuke",
		label = "Nuke",
		icon = assets.Icons.nuke,
		group = "actions",
		order = 1,
		visible = function()
			return not PvpController.isActive()
		end,
		onClick = function()
			StoreController.promptProduct(Constants.PRODUCTS.NUKE)
		end,
	})

	Sidebar.registerEntry({
		id = "TowerNukeOthers",
		label = "Nuke Others",
		icon = assets.Icons.nuke,
		group = "actions",
		-- Same seat as the classic Nuke, which it stands in for. The two are never
		-- on the rail together, so they can't collide over it.
		order = 1,
		visible = function()
			return PvpController.isActive()
		end,
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
		visible = function()
			return not PvpController.isActive()
		end,
		onClick = function()
			StoreController.promptProduct(Constants.PRODUCTS.NEXT_CHECKPOINT)
		end,
	})

	-- The registry can't see a match start, and the state packet lands many times
	-- a second — so the rail is told once, on the edge, rather than on every
	-- broadcast. Without this the buttons would still be right, but only after
	-- something else happened to make the rail re-render.
	local wasActive = PvpController.isActive()
	PvpController.DataChanged:Connect(function()
		local active = PvpController.isActive()
		if active == wasActive then
			return
		end
		wasActive = active
		Sidebar.refresh()
	end)
end

return {}
