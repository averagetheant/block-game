--!nonstrict
-- UI Labs story for the left rail. Wrapped in UIShell.FrameProvider so
-- useFrame() resolves in the preview (production mounts the provider once at
-- the client root).
--
-- The entries and window contents are injected rather than read from the live
-- registries: in UI Labs no feature has registered anything, so the rail would
-- otherwise render empty and there'd be nothing to look at.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Features = ReplicatedStorage:WaitForChild("Features")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local ui = require(ReplicatedStorage.Shared.Boil).ui
local UIShell = require(Features:WaitForChild("UIShell"))

local Sidebar = require(Features:WaitForChild("Sidebar"))

local ICON = ui.assets.Icons.shoppingBasket
local CASH = ui.assets.Icons.bandOfCash

local function placeholder(label: string)
	return React.createElement(ui.Text, {
		text = `{label} content goes here`,
		textSize = ui.theme.textSizeRegular,
		size = UDim2.new(1, 0, 0, 60),
	})
end

return {
	summary = "The left rail: a 'menu' cluster that toggles Window frames above an 'actions' cluster of one-shot buttons. Click an icon to open its frame — the rail slides off-screen while one is up.",
	react = React,
	reactRoblox = ReactRoblox,

	story = function()
		return React.createElement(UIShell.FrameProvider, {}, {
			Rail = React.createElement(Sidebar.Rail, {
				menu = {
					{ id = "Shop", icon = ICON, label = "Shop", order = 1, titleVariant = "yellow" },
					{ id = "Inventory", icon = ICON, label = "Inventory", order = 2, titleVariant = "green" },
				},
				actions = {
					{
						id = "Nuke",
						icon = CASH,
						label = "Nuke",
						order = 1,
						group = "actions",
						onClick = function()
							print("[Sidebar] Nuke clicked")
						end,
					},
					{
						id = "Skip",
						icon = CASH,
						label = "Skip",
						order = 2,
						group = "actions",
						onClick = function()
							print("[Sidebar] Skip clicked")
						end,
					},
				},
				frameContents = {
					Shop = placeholder("Shop"),
					Inventory = placeholder("Inventory"),
				},
			}),
		})
	end,
}
