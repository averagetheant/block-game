--!strict
-- Pure/dumb HUD for TowerGame. Takes the whole game state as props and renders
-- it; owns no data fetching, no networking, no clock. TowerView wires it to the
-- controller store, and TowerHUD.story drives it from sliders in UI Labs.
--
-- Layout note: this is a full-screen gameplay HUD, not a window, so it hugs the
-- edges rather than following the centered-by-default rule for feature UIs.
-- Centering a height readout would sit it on top of the tower being aimed at.
--
--   top center     turn strip → height/best → turn clock → storm clock
--   bottom left    controls hint (fades out on its own)
--   bottom center  touch controls (touch devices only)
--
-- The top column flows through one Stack rather than being positioned by hand,
-- so a row appearing or disappearing (the turn clock only exists while someone
-- is aiming) reflows the rest instead of leaving a hole.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ui = require(ReplicatedStorage.Shared.Boil).ui
local Constants = require(script.Parent.Constants)
local ControlsHint = require(script.Parent.ControlsHint)
local TurnStrip = require(script.Parent.TurnStrip)

local PHASE = Constants.PHASE

local COLUMN_WIDTH = 420
local STATS_HEIGHT = 62
local STATUS_HEIGHT = 34
local BAR_HEIGHT = 26
local STAT_TEXT_SIZE = 30
local STATUS_TEXT_SIZE = 26
local TOP_MARGIN = 10
local STACK_GAP = 6

local BUTTON_SIZE = UDim2.fromOffset(110, 88)
local DROP_SIZE = UDim2.fromOffset(160, 88)
local CONTROL_GAP = 12
local EDGE_MARGIN = 20
local CONTROL_ROW_HEIGHT = 88
local CONTROL_ROW_WIDTH = 110 * 3 + 160 + CONTROL_GAP * 3

-- Under this many seconds the turn clock turns red.
local URGENT_SECONDS = 5
-- Under this many seconds the storm clock turns red.
local STORM_URGENT_SECONDS = 30

export type Props = {
	height: number,
	maxHeight: number,
	blockCount: number,
	phase: number,
	isMyTurn: boolean,
	-- Display name of whoever holds the piece; nil when nobody does.
	holderName: string?,
	holderUserId: number,
	-- Turn order as user ids, current holder first.
	order: { number },
	shapeName: string,
	nextShapeName: string,
	secondsLeft: number,
	turnSeconds: number,
	-- Storm stage: the height to beat, the clock, and floors earned so far.
	targetHeight: number,
	stormSecondsLeft: number,
	stormSeconds: number,
	checkpoints: number,
	device: ControlsHint.Device,
	showControls: boolean?,
	showHint: boolean?,
	onMoveLeft: (() -> ())?,
	onMoveRight: (() -> ())?,
	onRotate: (() -> ())?,
	onDrop: (() -> ())?,
}

local function clock(seconds: number): string
	local whole = math.max(math.ceil(seconds), 0)
	return string.format("%d:%02d", whole // 60, whole % 60)
end

local function statusLine(props: Props): string
	if props.phase == PHASE.IDLE then
		return "Waiting for players…"
	end
	if props.phase == PHASE.SETTLING then
		return "Settling…"
	end
	if props.isMyTurn then
		return `Your turn — {props.shapeName} piece`
	end
	return `{props.holderName or "Someone"} is placing the {props.shapeName}`
end

return function(props: Props)
	local aiming = props.phase == PHASE.AIMING
	local canAct = aiming and props.isMyTurn
	local toGo = math.max(props.targetHeight - props.height, 0)

	local column: { [string]: any } = {
		Turns = React.createElement(TurnStrip, {
			order = props.order,
			holderUserId = props.holderUserId,
			layoutOrder = 1,
		}),

		-- Height is the score, so it gets the weight; best sits alongside it at
		-- the same size but dimmer, and the block count moved to the leaderboard.
		Stats = React.createElement(ui.Panel, {
			size = UDim2.new(1, 0, 0, STATS_HEIGHT),
			layoutOrder = 2,
		}, {
			Row = React.createElement(ui.Row, { size = UDim2.fromScale(1, 1) }, {
				Height = React.createElement(ui.Text, {
					text = `{string.format("%.1f", props.height)} studs`,
					textSize = STAT_TEXT_SIZE,
					weight = Enum.FontWeight.Heavy,
					shadow = true,
					xAlignment = Enum.TextXAlignment.Center,
					size = UDim2.new(0.55, 0, 1, 0),
					layoutOrder = 1,
				}),
				Best = React.createElement(ui.Text, {
					text = `best {string.format("%.1f", props.maxHeight)}`,
					textSize = STAT_TEXT_SIZE - 6,
					color = Color3.fromRGB(184, 192, 214),
					xAlignment = Enum.TextXAlignment.Center,
					size = UDim2.new(0.45, 0, 1, 0),
					layoutOrder = 2,
				}),
			}),
		}),

		Status = React.createElement(ui.Text, {
			text = statusLine(props),
			textSize = STATUS_TEXT_SIZE,
			weight = Enum.FontWeight.Bold,
			shadow = true,
			xAlignment = Enum.TextXAlignment.Center,
			size = UDim2.new(1, 0, 0, STATUS_HEIGHT),
			layoutOrder = 3,
		}),

		Storm = React.createElement(ui.ProgressBar, {
			progress = math.clamp(props.stormSecondsLeft / math.max(props.stormSeconds, 1), 0, 1),
			variant = if props.stormSecondsLeft <= STORM_URGENT_SECONDS then "red" else "purple",
			text = `STORM {clock(props.stormSecondsLeft)} — {string.format("%.0f", toGo)} to go`,
			showText = true,
			size = UDim2.new(1, 0, 0, BAR_HEIGHT),
			layoutOrder = 5,
		}),
	}

	-- The turn clock only exists while someone is aiming, so the bar comes and
	-- goes with the phase rather than sitting at 0 between turns.
	if aiming then
		column.Timer = React.createElement(ui.ProgressBar, {
			progress = math.clamp(props.secondsLeft / math.max(props.turnSeconds, 1), 0, 1),
			variant = if props.secondsLeft <= URGENT_SECONDS then "red" else "green",
			text = `{math.ceil(props.secondsLeft)}s`,
			showText = true,
			size = UDim2.new(1, 0, 0, BAR_HEIGHT),
			layoutOrder = 4,
		})
	end

	local children: { [string]: any } = {
		Column = React.createElement(ui.Stack, {
			gap = STACK_GAP,
			size = UDim2.fromOffset(COLUMN_WIDTH, 0),
			automaticSize = Enum.AutomaticSize.Y,
			position = UDim2.new(0.5, 0, 0, TOP_MARGIN),
			anchorPoint = Vector2.new(0.5, 0),
		}, column),
	}

	if props.showHint ~= false then
		children.Hint = React.createElement(ControlsHint, {
			device = props.device,
			position = UDim2.new(0, EDGE_MARGIN, 1, -EDGE_MARGIN),
			anchorPoint = Vector2.new(0, 1),
		})
	end

	if props.showControls then
		children.Controls = React.createElement(ui.Row, {
			gap = CONTROL_GAP,
			size = UDim2.fromOffset(CONTROL_ROW_WIDTH, CONTROL_ROW_HEIGHT),
			position = UDim2.new(0.5, 0, 1, -EDGE_MARGIN),
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
