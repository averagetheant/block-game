--!strict
-- Pure/dumb HUD for TowerGame. Takes the whole game state as props and renders
-- it; owns no data fetching, no networking, no clock. TowerView wires it to the
-- controller store, and TowerHUD.story drives it from sliders in UI Labs.
--
-- Layout note: this is a full-screen gameplay HUD, not a window, so it hugs the
-- edges — readouts top-center, controls bottom-center — rather than following the
-- centered-by-default rule for feature UIs. Centering a height readout would sit
-- it directly on top of the tower the player is aiming at.
--
-- The controls row renders on touch devices only (TowerView decides). PC and
-- console are bound through ContextActionService in TowerInputController, so
-- every platform ends up calling the same four intents.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ui = require(ReplicatedStorage.Shared.Boil).ui
local Constants = require(script.Parent.Constants)

local PHASE = Constants.PHASE

local READOUT_WIDTH = 480
local READOUT_HEIGHT = 84
local STATUS_HEIGHT = 44
local TIMER_HEIGHT = 30
local STAT_TEXT_SIZE = 34
local STATUS_TEXT_SIZE = 32
local TOP_MARGIN = 14
local STACK_GAP = 8

local BUTTON_SIZE = UDim2.fromOffset(120, 96)
local DROP_SIZE = UDim2.fromOffset(180, 96)
local CONTROL_GAP = 14
local BOTTOM_MARGIN = 24
local CONTROL_ROW_HEIGHT = 96
local CONTROL_ROW_WIDTH = 120 * 3 + 180 + CONTROL_GAP * 3

-- Under this many seconds the timer bar turns red.
local URGENT_SECONDS = 5

export type Props = {
	height: number,
	maxHeight: number,
	blockCount: number,
	phase: number,
	isMyTurn: boolean,
	-- Display name of whoever holds the piece; nil when nobody does.
	holderName: string?,
	shapeName: string,
	nextShapeName: string,
	secondsLeft: number,
	turnSeconds: number,
	showControls: boolean?,
	onMoveLeft: (() -> ())?,
	onMoveRight: (() -> ())?,
	onRotate: (() -> ())?,
	onDrop: (() -> ())?,
}

local function stat(layoutOrder: number, label: string, value: string): any
	return React.createElement(ui.Text, {
		text = `{label}\n{value}`,
		textSize = STAT_TEXT_SIZE,
		weight = Enum.FontWeight.Heavy,
		shadow = true,
		xAlignment = Enum.TextXAlignment.Center,
		yAlignment = Enum.TextYAlignment.Center,
		size = UDim2.new(1 / 3, 0, 1, 0),
		layoutOrder = layoutOrder,
	})
end

local function statusLine(props: Props): string
	if props.phase == PHASE.IDLE then
		return "Waiting for players…"
	end
	if props.phase == PHASE.SETTLING then
		return "Settling…"
	end
	if props.isMyTurn then
		return `Your turn — drop the {props.shapeName}`
	end
	return `{props.holderName or "Someone"} is placing the {props.shapeName}`
end

return function(props: Props)
	local aiming = props.phase == PHASE.AIMING
	local urgent = aiming and props.secondsLeft <= URGENT_SECONDS
	local canAct = aiming and props.isMyTurn

	local children: { [string]: any } = {
		-- Top-center: the numbers that matter, always on screen.
		Readouts = React.createElement(ui.Stack, {
			gap = STACK_GAP,
			size = UDim2.fromOffset(READOUT_WIDTH, 0),
			automaticSize = Enum.AutomaticSize.Y,
			position = UDim2.new(0.5, 0, 0, TOP_MARGIN),
			anchorPoint = Vector2.new(0.5, 0),
		}, {
			Stats = React.createElement(ui.Panel, {
				size = UDim2.new(1, 0, 0, READOUT_HEIGHT),
				layoutOrder = 1,
			}, {
				Row = React.createElement(ui.Row, {
					size = UDim2.fromScale(1, 1),
				}, {
					Height = stat(1, "HEIGHT", string.format("%.1f", props.height)),
					Best = stat(2, "BEST", string.format("%.1f", props.maxHeight)),
					Blocks = stat(3, "BLOCKS", tostring(props.blockCount)),
				}),
			}),

			Status = React.createElement(ui.Text, {
				text = statusLine(props),
				textSize = STATUS_TEXT_SIZE,
				weight = Enum.FontWeight.Bold,
				shadow = true,
				xAlignment = Enum.TextXAlignment.Center,
				size = UDim2.new(1, 0, 0, STATUS_HEIGHT),
				layoutOrder = 2,
			}),
		}),
	}

	-- The turn clock only exists while someone is aiming, so the bar comes and
	-- goes with the phase rather than sitting at 0 between turns.
	if aiming then
		children.Timer = React.createElement(ui.ProgressBar, {
			progress = math.clamp(props.secondsLeft / math.max(props.turnSeconds, 1), 0, 1),
			variant = if urgent then "red" else "green",
			text = `{math.ceil(props.secondsLeft)}s`,
			showText = true,
			size = UDim2.fromOffset(READOUT_WIDTH, TIMER_HEIGHT),
			position = UDim2.new(0.5, 0, 0, TOP_MARGIN + READOUT_HEIGHT + STATUS_HEIGHT + STACK_GAP * 2),
			anchorPoint = Vector2.new(0.5, 0),
		})
	end

	if props.showControls then
		children.Controls = React.createElement(ui.Row, {
			gap = CONTROL_GAP,
			size = UDim2.fromOffset(CONTROL_ROW_WIDTH, CONTROL_ROW_HEIGHT),
			position = UDim2.new(0.5, 0, 1, -BOTTOM_MARGIN),
			anchorPoint = Vector2.new(0.5, 1),
		}, {
			Left = React.createElement(ui.Button, {
				variant = "blue",
				text = "LEFT",
				size = BUTTON_SIZE,
				disabled = not canAct,
				layoutOrder = 1,
				onClick = props.onMoveLeft,
			}),
			Rotate = React.createElement(ui.Button, {
				variant = "purple",
				text = "TURN",
				size = BUTTON_SIZE,
				disabled = not canAct,
				layoutOrder = 2,
				onClick = props.onRotate,
			}),
			Right = React.createElement(ui.Button, {
				variant = "blue",
				text = "RIGHT",
				size = BUTTON_SIZE,
				disabled = not canAct,
				layoutOrder = 3,
				onClick = props.onMoveRight,
			}),
			Drop = React.createElement(ui.Button, {
				variant = "red",
				text = "DROP",
				size = DROP_SIZE,
				disabled = not canAct,
				layoutOrder = 4,
				onClick = props.onDrop,
			}),
		})
	end

	return React.createElement("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, children)
end
