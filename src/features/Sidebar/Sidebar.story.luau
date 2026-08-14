--!nonstrict
-- UI Labs story for the Sidebar. Renders a column of clickable icons with
-- their labels overlaid inside the bottom of each icon. Click to print.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local UILabs = require(ReplicatedStorage.Packages.UILabs)

local Sidebar = require(ReplicatedStorage.Features.Sidebar)

-- Placeholder until you upload your own icons.
local PLACEHOLDER_ICON = "rbxassetid://137349421699691"

return {
	summary = "Sidebar column — icon-only entries with the label overlaid inside each icon at the bottom.",
	react = React,
	reactRoblox = ReactRoblox,

	controls = {
		iconSize = UILabs.Slider(72, 24, 160, 1),
		-- Starts at the real default rather than an arbitrary small value, so
		-- the story opens on what the game actually renders.
		labelSize = UILabs.Slider(Sidebar.Constants.DEFAULT_LABEL_SIZE, 8, 60, 1),
		spacing = UILabs.Slider(12, 0, 40, 1),
	},

	story = function(props)
		local c = props.controls
		return React.createElement(Sidebar.UI, {
			iconSize = c.iconSize,
			labelSize = c.labelSize,
			spacing = c.spacing,
			position = UDim2.fromScale(0.5, 0.5),
			anchorPoint = Vector2.new(0.5, 0.5),
			items = {
				{
					id = "Shop",
					icon = PLACEHOLDER_ICON,
					label = "Shop",
					onClick = function() print("[Sidebar] Shop clicked") end,
				},
				{
					id = "Inventory",
					icon = PLACEHOLDER_ICON,
					label = "Inventory",
					onClick = function() print("[Sidebar] Inventory clicked") end,
				},
				{
					id = "Quests",
					icon = PLACEHOLDER_ICON,
					label = "Quests",
					onClick = function() print("[Sidebar] Quests clicked") end,
				},
				{
					id = "Settings",
					icon = PLACEHOLDER_ICON,
					label = "Settings",
					onClick = function() print("[Sidebar] Settings clicked") end,
				},
			},
		})
	end,
}
