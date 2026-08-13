-- Wires the Reactions inventory tab to live data: the current bar, and which
-- reactions the player can actually use.
--
-- Ownership is a Store question (a reaction is unlocked by owning its pack), so
-- it's read through the controller rather than off a Reactions field — there's
-- one source of truth for "bought", and it isn't here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

local Boil = require(ReplicatedStorage.Shared.Boil)
local Catalog = require(ReplicatedStorage.Features.Reactions.Catalog)
local ReactionInventory = require(ReplicatedStorage.Features.Reactions.ReactionInventory)

-- Client-realm siblings (StarterPlayerScripts.Features tree).
local ReactionsController = require(script.Parent.ReactionsController)
local PlayerDataController = require(script.Parent.Parent.PlayerData.PlayerDataController)

return function()
	-- The whole profile, because this tab reads two slices: Reactions for the
	-- bar and Store for what's unlocked.
	Boil.useReplica(PlayerDataController)

	local owned: { [string]: boolean } = {}
	for _, reaction in Catalog.List do
		owned[reaction.id] = ReactionsController.owns(reaction.id)
	end

	return React.createElement(ReactionInventory, {
		slots = ReactionsController.slots(),
		owned = owned,
		onAssign = ReactionsController.setSlot,
	})
end
