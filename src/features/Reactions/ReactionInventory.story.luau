--!nonstrict
-- UI Labs story for the Reactions inventory tab. Slot assignment is real (state
-- lives in the story), ownership is a control — in game it comes from whether
-- the Emoji Pack has been bought.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Features = ReplicatedStorage:WaitForChild("Features")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local ui = require(ReplicatedStorage.Shared.Boil).ui

local Reactions = require(Features:WaitForChild("Reactions"))

return {
	summary = "Reactions tab: pick a bar slot up top, then a reaction below to fill it. Turn `ownsPack` off to see the locked state — unowned reactions stay visible and dimmed, because hiding them hides the reason to buy the pack.",
	react = React,
	reactRoblox = ReactRoblox,

	controls = {
		ownsPack = true,
	},

	story = function(props)
		local ownsPack = props.controls.ownsPack
		local slots, setSlots = React.useState(table.clone(Reactions.Catalog.DEFAULT_SLOTS))

		local owned = {}
		for _, reaction in Reactions.Catalog.List do
			owned[reaction.id] = reaction.pack == nil or ownsPack
		end

		return React.createElement(ui.Window, {
			title = "Inventory",
			icon = ui.assets.Icons.book,
			titleVariant = "green",
			size = UDim2.fromOffset(820, 600),
		}, {
			Content = React.createElement(Reactions.Inventory, {
				slots = slots,
				owned = owned,
				onAssign = function(index, reactionId)
					setSlots(function(current)
						local next = table.clone(current)
						next[index] = reactionId
						return next
					end)
				end,
			}),
		})
	end,
}
