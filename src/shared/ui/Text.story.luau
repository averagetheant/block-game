--!nonstrict
-- UI Labs story for the Text primitive. Toggle the shadow control to compare
-- the plain label against the gem drop-shadow variant.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local UILabs = require(ReplicatedStorage.Packages.UILabs)
local ui = require(ReplicatedStorage.Shared.ui)

return {
	summary = "Text primitive — toggle `shadow` for the drop-shadow gem treatment, "
		.. "or narrow the box with `fit` on to watch the label give size back "
		.. "instead of spilling out of it.",
	react = React,
	reactRoblox = ReactRoblox,

	controls = {
		text = "Hello",
		textSize = UILabs.Slider(50, 8, 200, 1),
		shadow = false,
		-- Shrink the box, not the text: this is the control that reproduces what
		-- a phone does to a label authored against the 1280x720 reference.
		boxWidth = UILabs.Slider(600, 60, 900, 10),
		boxHeight = UILabs.Slider(80, 20, 400, 10),
		wrapped = false,
		fit = false,
		weight = UILabs.Choose({
			"Bold", "Heavy", "SemiBold", "Medium", "Regular",
		}),
		xAlignment = UILabs.Choose({ "Center", "Left", "Right" }),
	},

	story = function(props)
		local c = props.controls
		return React.createElement(ui.Text, {
			text = c.text,
			textSize = c.textSize,
			shadow = c.shadow,
			wrapped = c.wrapped,
			fit = c.fit,
			weight = Enum.FontWeight[c.weight],
			xAlignment = Enum.TextXAlignment[c.xAlignment],
			size = UDim2.fromOffset(c.boxWidth, c.boxHeight),
			position = UDim2.fromScale(0.5, 0.5),
			anchorPoint = Vector2.new(0.5, 0.5),
		})
	end,
}
