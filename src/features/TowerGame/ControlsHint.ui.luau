--!strict
-- Bottom-left control list, sized to the device it's read on, gone after a
-- minute. New players need it once; everyone else shouldn't have to look at it
-- for the rest of the session.
--
-- The fade is a tween on a CanvasGroup rather than React state so the whole
-- subtree dissolves as one, and so the animation costs no re-renders.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local React = require(ReplicatedStorage.Packages.React)
local ui = require(ReplicatedStorage.Shared.Boil).ui
local Constants = require(script.Parent.Constants)

export type Device = "pc" | "touch" | "gamepad"

export type Props = {
	device: Device,
	position: UDim2?,
	anchorPoint: Vector2?,
}

local LINES: { [string]: { string } } = {
	pc = {
		"Move — A / D, or aim with the mouse",
		"Rotate — W",
		"Drop — click or Space",
	},
	touch = {
		"Move — LEFT / RIGHT",
		"Rotate — TURN",
		"Drop — DROP",
	},
	gamepad = {
		"Move — D-Pad left / right",
		"Rotate — Y",
		"Drop — A",
	},
}

local WIDTH = 320
local LINE_HEIGHT = 26
local TEXT_SIZE = 22
local PADDING = 10

return function(props: Props)
	local group = React.useRef(nil :: CanvasGroup?)

	React.useEffect(function()
		local active = true

		task.delay(Constants.HINT_SECONDS, function()
			if not active then
				return
			end
			local instance = group.current
			if instance == nil then
				return
			end
			TweenService:Create(
				instance,
				TweenInfo.new(Constants.HINT_FADE_SECONDS),
				{ GroupTransparency = 1 }
			):Play()
		end)

		-- Unmounting before the timer fires must not leave a tween pointed at a
		-- destroyed instance.
		return function()
			active = false
		end
	end, {})

	local lines = LINES[props.device] or LINES.pc

	local children: { [string]: any } = {}
	for index, line in lines do
		children[`Line{index}`] = React.createElement(ui.Text, {
			text = line,
			textSize = TEXT_SIZE,
			color = Color3.fromRGB(226, 230, 245),
			xAlignment = Enum.TextXAlignment.Left,
			size = UDim2.new(1, 0, 0, LINE_HEIGHT),
			layoutOrder = index,
		})
	end

	return React.createElement("CanvasGroup", {
		ref = group,
		Size = UDim2.fromOffset(WIDTH, #lines * LINE_HEIGHT + PADDING * 2),
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, {
		Stack = React.createElement(ui.Stack, {
			padding = PADDING,
			horizontalAlignment = Enum.HorizontalAlignment.Left,
		}, children),
	})
end
