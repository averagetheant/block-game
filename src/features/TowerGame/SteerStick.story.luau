--!nonstrict
-- UI Labs story for the touch steering stick.
--
-- Draggable with the mouse as well as a finger, so the feel can be checked in
-- the editor without an emulator: the component treats MouseButton1 as a touch.
-- The live readout under it is the value `setSteer` would receive — watch that
-- it reaches exactly ±1 at the ends and snaps to 0 the instant you let go,
-- because a stick that stayed put would leave the piece sliding.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Features = ReplicatedStorage:WaitForChild("Features")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local UILabs = require(ReplicatedStorage.Packages.UILabs)
local ui = require(ReplicatedStorage.Shared.Boil).ui

local TowerGame = Features:WaitForChild("TowerGame")
local SteerStick = require(TowerGame:WaitForChild("SteerStick"))

return {
	summary = "Touch steering, gem-styled. Drag the knob (mouse works too); the readout "
		.. "is the analog value handed to `setSteer`. Releasing must return 0. "
		.. "`variant` swaps the knob's gem palette.",
	react = React,
	reactRoblox = ReactRoblox,

	controls = {
		variant = UILabs.Choose({
			"blue", "red", "green", "purple", "yellow", "white", "rainbow",
		}),
		disabled = false,
	},

	story = function(props)
		local value, setValue = React.useState(0)

		return React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
		}, {
			Stick = React.createElement(SteerStick, {
				variant = props.controls.variant,
				disabled = props.controls.disabled,
				position = UDim2.fromScale(0.5, 0.5),
				anchorPoint = Vector2.new(0.5, 0.5),
				onSteer = setValue,
			}),

			Readout = React.createElement("TextLabel", {
				Size = UDim2.new(1, 0, 0, ui.theme.textSizeRegular + 4),
				Position = UDim2.new(0.5, 0, 0.5, 70),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundTransparency = 1,
				Text = string.format("steer = %+.2f", value),
				TextColor3 = Color3.fromRGB(226, 230, 245),
				TextSize = ui.theme.textSizeRegular,
			}),
		})
	end,
}
