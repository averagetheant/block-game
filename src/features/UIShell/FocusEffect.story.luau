--!nonstrict
-- UI Labs story for the focus effect. It renders no UI of its own — the thing to
-- watch is the *viewport behind the story*: flip `isOpen` and the world blurs
-- while the camera eases in a few degrees of FOV.
--
-- In game nothing mounts this by hand; FrameProvider does, so every frame gets
-- the effect. The toggle here is what `openFrameId ~= nil` does at runtime.
--
-- Both halves undo themselves when the story unmounts, so closing the story
-- can't leave the place blurred.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local ui = require(ReplicatedStorage.Shared.Boil).ui

local FocusEffect = require(ReplicatedStorage.Features.UIShell.FocusEffect)

return {
	summary = "The blur + FOV zoom every UIShell frame gets. No UI of its own — flip isOpen and watch the viewport behind the story.",
	react = React,
	reactRoblox = ReactRoblox,

	controls = {
		isOpen = false,
	},

	story = function(props)
		return React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
		}, {
			Effect = React.createElement(FocusEffect, { isOpen = props.controls.isOpen }),

			-- A stand-in for the frame that would normally be on screen, so the
			-- effect has something to be behind.
			Card = React.createElement(ui.Panel, {
				size = UDim2.fromOffset(360, 160),
				position = UDim2.fromScale(0.5, 0.5),
				anchorPoint = Vector2.new(0.5, 0.5),
			}, {
				Label = React.createElement(ui.Text, {
					text = if props.controls.isOpen then "focused" else "no frame open",
					textSize = ui.theme.textSizeRegular,
					weight = Enum.FontWeight.Heavy,
					shadow = true,
					size = UDim2.fromScale(1, 1),
				}),
			}),
		})
	end,
}
