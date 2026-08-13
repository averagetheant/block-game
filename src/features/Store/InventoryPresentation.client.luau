-- Screen presentation for the inventory: registers the inventory window's
-- content into its frame slot. Registration is the only side effect.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local UIRegistry = require(ReplicatedStorage.Shared.Boil).UIRegistry
local Constants = require(ReplicatedStorage.Features.Store.Constants)

-- Client-realm sibling (StarterPlayerScripts.Features.Store.InventoryView).
local InventoryView = require(script.Parent.InventoryView)

if Constants.Presentations.inventory then
	UIRegistry.registerScreen(Constants.INVENTORY_FRAME_ID, React.createElement(InventoryView))
end

return {}
