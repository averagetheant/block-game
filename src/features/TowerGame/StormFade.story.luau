--!nonstrict
-- UI Labs story for the storm white-out.
--
-- The effect is a one-shot on the rising edge of `active`, so a plain checkbox
-- would only ever fire it once. `replay` re-mounts the component instead, which
-- is the reliable way to watch the sequence again — and it's also what the live
-- game does, since the fade mounts with the round break.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Features = ReplicatedStorage:WaitForChild("Features")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local UILabs = require(ReplicatedStorage.Packages.UILabs)

local TowerGame = Features:WaitForChild("TowerGame")
local Constants = require(TowerGame:WaitForChild("Constants"))
local StormFade = require(TowerGame:WaitForChild("StormFade"))

return {
	summary = "The storm's white-out. `active` plays the whole flash once: "
		.. `{Constants.STORM_FADE_DELAY_SECONDS}s of nothing (the blocks are flying), `
		.. `fade in over {Constants.STORM_FADE_IN_SECONDS}s, hold `
		.. `{Constants.STORM_FADE_HOLD_SECONDS}s, clear over {Constants.STORM_FADE_OUT_SECONDS}s. `
		.. "Toggle `replay` to run it again.",
	react = React,
	reactRoblox = ReactRoblox,

	controls = {
		active = true,
		replay = false,
	},

	story = function(props)
		local c = props.controls

		return React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(28, 32, 48),
			BorderSizePixel = 0,
		}, {
			-- Something behind the sheet, so "fading to white" is visibly covering
			-- a scene rather than just filling an empty frame.
			Behind = React.createElement("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = "the tower was here",
				TextColor3 = Color3.fromRGB(150, 160, 200),
				TextSize = 42,
			}),

			-- Keyed on `replay` so flipping it remounts and replays the sequence.
			Fade = React.createElement(StormFade, {
				active = c.active,
				key = if c.replay then "replay" else "initial",
			}),
		})
	end,
}
