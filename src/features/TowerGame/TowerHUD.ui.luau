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
local TweenService = game:GetService("TweenService")

local React = require(ReplicatedStorage.Packages.React)
local ui = require(ReplicatedStorage.Shared.Boil).ui
local CashFly = require(script.Parent.CashFly)
local Constants = require(script.Parent.Constants)
local ControlsHint = require(script.Parent.ControlsHint)
local ProgressLine = require(script.Parent.ProgressLine)
local RadialTimer = require(script.Parent.RadialTimer)
local SteerStick = require(script.Parent.SteerStick)
local StormFade = require(script.Parent.StormFade)
local TurnStrip = require(script.Parent.TurnStrip)
local Zones = require(script.Parent.Zones)

local PHASE = Constants.PHASE

-- Text sizes and the boxes that hold them move together. Every height here is
-- sized against the text inside it, so bumping a size without its box is what
-- clips a descender or crops a status line — and the column width is what a long
-- one ("SomePlayer is placing the Bomb T-Shape") has to fit inside.
local COLUMN_WIDTH = 460
local STATS_HEIGHT = 66
local STATUS_HEIGHT = 38
local STAT_TEXT_SIZE = 34
local STATUS_TEXT_SIZE = 30
local TOP_MARGIN = 10
local STACK_GAP = 6

local BUTTON_SIZE = UDim2.fromOffset(110, 88)
local DROP_SIZE = UDim2.fromOffset(160, 88)
local CONTROL_GAP = 12
local EDGE_MARGIN = 20
local CONTROL_ROW_HEIGHT = 88
-- The steering stick, then TURN and DROP, with a double gap between the stick
-- and the buttons.
local CONTROL_ROW_WIDTH = Constants.STICK_TRACK_WIDTH + 110 + 160 + CONTROL_GAP * 4

local STORM_LABEL_HEIGHT = 28
local STORM_LABEL_TEXT_SIZE = 25
local PROGRESS_HEIGHT = 26
local PANEL_RESIZE = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- The camera toggle, sitting above the cash panel on the right edge.
local CAMERA_BUTTON = 62
local CASH_WIDTH = 205
local CASH_HEIGHT = 58
local CASH_TEXT_SIZE = 32
local CASH_ICON = 34
local WARNING_WIDTH = 460
local WARNING_HEIGHT = 104

-- The storm's white-out covers the screen, and the HUD is part of the screen —
-- so it sits above every other child rather than among them.
local FADE_Z_INDEX = 100

-- Under this many seconds the turn clock turns red.
local URGENT_SECONDS = 5
-- Under this many seconds the storm clock turns red.
local STORM_URGENT_SECONDS = 30

-- Where the bills land. Kept in step with the counter's own anchor below.
local CASH_TARGET = UDim2.new(1, -(EDGE_MARGIN + CASH_WIDTH / 2), 1, -(EDGE_MARGIN + CASH_HEIGHT / 2))

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
	-- Height this leg of the climb started at; the progress line runs from here.
	zoneBaseHeight: number,
	stormSecondsLeft: number,
	stormSeconds: number,
	checkpoints: number,
	device: ControlsHint.Device,
	cash: number,
	-- Signal firing with an amount whenever cash arrives; drives the bill burst.
	cashAwarded: any,
	-- Zone to warn about, or nil when there's nothing to shout about.
	zoneWarning: Zones.Zone?,
	showControls: boolean?,
	showHint: boolean?,
	-- Touch steering, -1 to 1. Continuous: the stick reports every drag frame and
	-- 0 exactly once when the thumb lifts.
	onSteer: ((value: number) -> ())?,
	-- Whether the camera is currently pulled back to show the whole tower. Only
	-- colours the button — the camera controller owns the state.
	overview: boolean?,
	onToggleCamera: (() -> ())?,
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
	if props.phase == PHASE.CHECKPOINT then
		return "Checkpoint! Clearing the tower…"
	end
	if props.phase == PHASE.GAMEOVER then
		return "The storm took the tower!"
	end
	if props.phase == PHASE.SETTLING then
		return "Settling…"
	end
	-- `shapeName` is the piece's full name ("Bomb T-Shape", "Noob"), the same
	-- text the block's own plate shows, so the two can't describe it differently.
	if props.isMyTurn then
		return `Your turn — {props.shapeName}`
	end
	return `{props.holderName or "Someone"} is placing the {props.shapeName}`
end

return function(props: Props)
	local aiming = props.phase == PHASE.AIMING
	local canAct = aiming and props.isMyTurn

	-- The height panel gives up room for the turn dial and takes it back between
	-- turns; tweened so the handover reads as one motion with the dial.
	local statsRef = React.useRef(nil :: GuiObject?)
	React.useEffect(function()
		local panel = statsRef.current
		if panel == nil then
			return
		end
		local width = if aiming then -(STATS_HEIGHT + 10) else 0
		local tween = TweenService:Create(panel, PANEL_RESIZE, { Size = UDim2.new(1, width, 0, STATS_HEIGHT) })
		tween:Play()
		return function()
			tween:Cancel()
			tween:Destroy()
		end
	end, { aiming } :: { any })

	local column: { [string]: any } = {
		Turns = React.createElement(TurnStrip, {
			order = props.order,
			holderUserId = props.holderUserId,
			layoutOrder = 1,
		}),

		-- Height, with the turn clock beside it. The dial only exists while
		-- someone is aiming, so between turns the panel takes the full width.
		HeightRow = React.createElement(ui.Row, {
			gap = 10,
			size = UDim2.new(1, 0, 0, STATS_HEIGHT),
			layoutOrder = 2,
		}, {
			Stats = React.createElement(ui.Panel, {
				-- Tweened rather than set: the dial appearing and disappearing
				-- each turn would otherwise snap the panel's width twice a turn.
				ref = statsRef,
				size = UDim2.new(1, 0, 0, STATS_HEIGHT),
				layoutOrder = 1,
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

			Timer = if aiming
				then React.createElement(RadialTimer, {
					progress = props.secondsLeft / math.max(props.turnSeconds, 1),
					color = if props.secondsLeft <= URGENT_SECONDS
						then Color3.fromRGB(232, 96, 96)
						else Color3.fromRGB(112, 214, 122),
					size = STATS_HEIGHT,
					label = tostring(math.ceil(props.secondsLeft)),
					layoutOrder = 2,
				})
				else nil,
		}),
	}

	-- The climb to the next checkpoint, as a journey between two dots rather
	-- than a bar: it measures this leg only, so every zone starts at the left.
	--
	-- Gone during the round break. The round is over, the tower it measured is
	-- wreckage, and the server has frozen `stormEndsAt` — but the client draws
	-- the clock as `stormEndsAt - now`, so leaving it up counts a dead deadline
	-- down behind the gamemode vote and then snaps back when the next round
	-- starts. Nothing to show is the honest answer.
	if props.phase ~= PHASE.GAMEOVER then
		column.Storm = React.createElement(ui.Stack, {
			gap = 2,
			size = UDim2.new(1, 0, 0, PROGRESS_HEIGHT + STORM_LABEL_HEIGHT + 2),
			layoutOrder = 3,
		}, {
			Line = React.createElement(ProgressLine, {
				from = props.zoneBaseHeight,
				current = props.height,
				to = props.targetHeight,
				size = UDim2.new(1, 0, 0, PROGRESS_HEIGHT),
				layoutOrder = 1,
			}),
			Countdown = React.createElement(ui.Text, {
				text = `{clock(props.stormSecondsLeft)} until storm!`,
				textSize = STORM_LABEL_TEXT_SIZE,
				weight = Enum.FontWeight.Bold,
				shadow = true,
				color = if props.stormSecondsLeft <= STORM_URGENT_SECONDS
					then Color3.fromRGB(255, 138, 122)
					else Color3.fromRGB(226, 230, 245),
				xAlignment = Enum.TextXAlignment.Center,
				size = UDim2.new(1, 0, 0, STORM_LABEL_HEIGHT),
				layoutOrder = 2,
			}),
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

		-- Whose turn it is, and what they're holding — down at the bottom where
		-- the player's attention already is when they're about to place.
		Status = React.createElement(ui.Text, {
			text = statusLine(props),
			textSize = STATUS_TEXT_SIZE,
			weight = Enum.FontWeight.Bold,
			shadow = true,
			xAlignment = Enum.TextXAlignment.Center,
			size = UDim2.new(0, COLUMN_WIDTH, 0, STATUS_HEIGHT),
			-- Clears the touch control row when there is one.
			position = UDim2.new(0.5, 0, 1, -(if props.showControls then CONTROL_ROW_HEIGHT + EDGE_MARGIN * 2 else EDGE_MARGIN)),
			anchorPoint = Vector2.new(0.5, 1),
		}),
	}

	-- Right edge, clear of the cash panel below it. Toggles the camera between
	-- following the tower and framing the whole thing.
	--
	-- On the right on purpose: the left rail is navigation (things that open a
	-- window), and this changes the view rather than opening anything.
	children.CameraToggle = React.createElement(ui.IconButton, {
		icon = ui.assets.Icons.magnifyingGlass,
		variant = if props.overview then "green" else "blue",
		size = UDim2.fromOffset(CAMERA_BUTTON, CAMERA_BUTTON),
		position = UDim2.new(1, -EDGE_MARGIN, 1, -(CASH_HEIGHT + EDGE_MARGIN * 2)),
		anchorPoint = Vector2.new(1, 1),
		onClick = props.onToggleCamera,
	})

	-- Bottom-right, opposite the controls hint. The bills fly here.
	children.Cash = React.createElement(ui.Panel, {
		size = UDim2.fromOffset(CASH_WIDTH, CASH_HEIGHT),
		position = UDim2.new(1, -EDGE_MARGIN, 1, -EDGE_MARGIN),
		anchorPoint = Vector2.new(1, 1),
	}, {
		Row = React.createElement(ui.Row, { gap = 8, size = UDim2.fromScale(1, 1) }, {
			Icon = React.createElement("ImageLabel", {
				Image = Constants.CASH_IMAGE,
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(CASH_ICON, CASH_ICON),
				LayoutOrder = 1,
			}),
			Amount = React.createElement(ui.Text, {
				text = tostring(props.cash),
				textSize = CASH_TEXT_SIZE,
				weight = Enum.FontWeight.Heavy,
				shadow = true,
				xAlignment = Enum.TextXAlignment.Left,
				size = UDim2.fromOffset(CASH_WIDTH - CASH_ICON - 34, CASH_HEIGHT),
				layoutOrder = 2,
			}),
		}),
	})

	children.CashFly = React.createElement(CashFly, {
		awarded = props.cashAwarded,
		target = CASH_TARGET,
	})

	-- Only special zones announce themselves; a normal zone is just a new sky.
	if props.zoneWarning then
		children.ZoneWarning = React.createElement(ui.Panel, {
			size = UDim2.fromOffset(WARNING_WIDTH, WARNING_HEIGHT),
			position = UDim2.fromScale(0.5, 0.34),
			anchorPoint = Vector2.new(0.5, 0.5),
			zIndex = 5,
		}, {
			Stack = React.createElement(ui.Stack, { gap = 2, padding = 8 }, {
				Title = React.createElement(ui.Text, {
					text = props.zoneWarning.name,
					textSize = 38,
					weight = Enum.FontWeight.Heavy,
					shadow = true,
					color = props.zoneWarning.tint,
					xAlignment = Enum.TextXAlignment.Center,
					size = UDim2.new(1, 0, 0, 46),
					layoutOrder = 1,
				}),
				Detail = React.createElement(ui.Text, {
					text = props.zoneWarning.warning or "",
					textSize = 27,
					weight = Enum.FontWeight.Bold,
					shadow = true,
					xAlignment = Enum.TextXAlignment.Center,
					size = UDim2.new(1, 0, 0, 34),
					layoutOrder = 2,
				}),
			}),
		})
	end

	if props.showHint ~= false then
		children.Hint = React.createElement(ControlsHint, {
			device = props.device,
			position = UDim2.new(0, EDGE_MARGIN, 1, -EDGE_MARGIN),
			anchorPoint = Vector2.new(0, 1),
		})
	end

	if props.showControls then
		-- Steering is a drag, the two actions are taps, so they're different
		-- shapes of control and sit apart: the stick on the left where a thumb
		-- rests, TURN and DROP on the right for the other one. The old LEFT /
		-- RIGHT buttons couldn't express how *far* to move — every placement was
		-- a burst of taps — which is what the stick fixes.
		children.Controls = React.createElement(ui.Row, {
			gap = CONTROL_GAP * 2,
			size = UDim2.fromOffset(CONTROL_ROW_WIDTH, CONTROL_ROW_HEIGHT),
			position = UDim2.new(0.5, 0, 1, -EDGE_MARGIN),
			anchorPoint = Vector2.new(0.5, 1),
		}, {
			Steer = React.createElement(SteerStick, {
				disabled = not canAct,
				layoutOrder = 1,
				onSteer = props.onSteer,
			}),
			Rotate = React.createElement(ui.Button, {
				variant = "purple",
				text = "TURN",
				size = BUTTON_SIZE,
				disabled = not canAct,
				layoutOrder = 2,
				onClick = props.onRotate,
			}),
			Drop = React.createElement(ui.Button, {
				variant = "red",
				text = "DROP",
				size = DROP_SIZE,
				disabled = not canAct,
				layoutOrder = 3,
				onClick = props.onDrop,
			}),
		})
	end

	-- Last child and highest ZIndex: the storm whites out everything, HUD included.
	children.StormFade = React.createElement(StormFade, {
		active = props.phase == PHASE.GAMEOVER,
		zIndex = FADE_Z_INDEX,
	})

	return React.createElement("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, children)
end
