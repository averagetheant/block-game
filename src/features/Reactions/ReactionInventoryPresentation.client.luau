-- Registers the Reactions tab into the Store's inventory window.
--
-- This is a *presentation* rather than a line in Reactions/Store.luau because
-- what it registers is a React element, and elements only exist on the client.
-- The shared Store.luau next door registers the pack; this registers the place
-- you go to use it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Constants = require(ReplicatedStorage.Features.Reactions.Constants)
local Store = require(ReplicatedStorage.Features.Store)

-- Client-realm sibling.
local ReactionInventoryView = require(script.Parent.ReactionInventoryView)

if Constants.Presentations.inventory then
	Store.registerInventoryTab({
		id = "reactions",
		title = "Reactions",
		order = 2,
		element = React.createElement(ReactionInventoryView),
	})
end

return {}
