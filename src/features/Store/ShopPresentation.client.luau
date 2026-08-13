-- Screen presentation for the shop: registers the shop window's content into
-- its frame slot. The Sidebar entry that opens that frame is declared in
-- Store/Sidebar.luau. Registration is the only side effect.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local UIRegistry = require(ReplicatedStorage.Shared.Boil).UIRegistry
local Constants = require(ReplicatedStorage.Features.Store.Constants)

-- Client-realm sibling (StarterPlayerScripts.Features.Store.ShopView).
local ShopView = require(script.Parent.ShopView)

if Constants.Presentations.shop then
	UIRegistry.registerScreen(Constants.SHOP_FRAME_ID, React.createElement(ShopView))
end

return {}
