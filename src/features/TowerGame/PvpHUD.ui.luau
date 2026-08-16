--!strict
-- Pure/dumb HUD for the PVP round. Takes the whole match as props and renders it;
-- owns no data fetching, no networking, no clock. `PvpView` wires it to the
-- controller store, and `PvpHUD.story` drives it from sliders in UI Labs.
--
-- It replaces the classic HUD rather than sitting beside it: everything that one
-- draws is about a turn queue and a storm, and neither exists here.
--
--   top center     match clock → your height and place → the zone
--   top right      the standings, every lane, tallest first
--   right, above   the map toggle (the classic HUD's camera button, doing the
--   the corner     PVP job: show the whole board instead of your own lane)
--   bottom left    controls hint (fades out on its own)
--   bottom center  touch controls (touch devices only)
--   center         the countdown, then the final standings
--
-- Layout note: a full-screen gameplay HUD, so it hugs the edges rather than
-- following the centered-by-default rule for feature UIs. The two things that
-- *are* centred are the two that own the moment rather than annotate it — the
-- countdown and the results — and both are up while nothing is being aimed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Boil = require(ReplicatedStorage.Shared.Boil)
local ui = Boil.ui
local Constants = require(script.Parent.Constants)
local ControlsHint = require(script.Parent.ControlsHint)
local PvpConstants = require(script.Parent.PvpConstants)
local RadialTimer = require(script.Parent.RadialTimer)
local SteerStick = require(script.Parent.SteerStick)

local PHASE = PvpConstants.PHASE

-- Shared with the classic HUD so the two can't disagree about where the screen
-- ends — a player switching modes between rounds should see things stay put.
local EDGE_MARGIN = Constants.EDGE_MARGIN
local TOP_MARGIN = 10
local STACK_GAP = 6

local COLUMN_WIDTH = 380
local CLOCK_HEIGHT = 72
local CLOCK_TEXT_SIZE = 52
local STATS_HEIGHT = 54
local STAT_TEXT_SIZE = 30
local ZONE_TEXT_SIZE = ui.theme.textSizeRegular
local ZONE_HEIGHT = ZONE_TEXT_SIZE + 8

-- The standings board. Sized for MAX_LANES rows so it never resizes as players
-- join or leave — a board that grew a row every time somebody arrived would
-- shuffle the whole right edge mid-match.
local BOARD_WIDTH = 260
local BOARD_ROW = 40
local BOARD_GAP = 4
local BOARD_PAD = 10
local BOARD_TITLE = 30
local BOARD_HEIGHT = BOARD_TITLE
	+ BOARD_GAP
	+ PvpConstants.MAX_LANES * BOARD_ROW
	+ (PvpConstants.MAX_LANES - 1) * BOARD_GAP
	+ BOARD_PAD * 2

local CONTROL_GAP = 12
local CONTROL_ROW_HEIGHT = 88
local CONTROL_ROW_WIDTH = Constants.STICK_TRACK_WIDTH + 110 + 160 + CONTROL_GAP * 4
local BUTTON_SIZE = UDim2.fromOffset(110, 88)
local DROP_SIZE = UDim2.fromOffset(160, 88)

local CAMERA_BUTTON = 62
-- The drop clock's dial, flanking the top column the same way the classic turn
-- dial does — outside it, so a piece being dealt can never move the readout.
local DIAL_SIZE = 74
local FLANK_Y = TOP_MARGIN + CLOCK_HEIGHT + STACK_GAP + STATS_HEIGHT / 2

local COUNTDOWN_TEXT_SIZE = 130
local RESULTS_WIDTH = 480
local RESULTS_ROW = 52
local RESULTS_TITLE = 44

-- Under this many seconds the match clock turns red. A quarter of the match is
-- too early to panic and ten seconds is too late to change anything.
local URGENT_SECONDS = 30

local YOU_COLOR = Color3.fromRGB(255, 214, 110)
local MUTED_COLOR = Color3.fromRGB(184, 192, 214)
local URGENT_COLOR = Color3.fromRGB(255, 138, 122)
-- The drop dial's two states, matched to the classic turn dial's so a player
-- reads "green is fine, red is now" the same way in both modes.
local DIAL_COLOR = Color3.fromRGB(112, 214, 122)
local DIAL_URGENT_COLOR = Color3.fromRGB(232, 96, 96)
-- Under this many seconds on the drop clock the dial turns red.
local DIAL_URGENT_SECONDS = 5
-- Gold, silver, bronze; everything past third draws in the ordinary colour.
local PLACE_COLORS = {
	Color3.fromRGB(255, 214, 110),
	Color3.fromRGB(214, 222, 240),
	Color3.fromRGB(226, 158, 106),
}

export type Entry = {
	userId: number,
	-- Resolved on the client, because a name resolved from a user id is one the
	-- player it belongs to can't have made up.
	name: string,
	height: number,
}

export type Props = {
	phase: number,
	-- Seconds left on whichever clock the phase is running.
	secondsLeft: number,
	matchSeconds: number,
	zoneName: string,
	-- Every lane, tallest first.
	standings: { Entry },
	-- This player's own row, or nil when they aren't in the match (spectating, or
	-- every seat was taken when they arrived).
	myHeight: number?,
	myRank: number,
	-- Whether they're aiming a piece, what it is, and how long they have.
	holding: boolean,
	pieceName: string,
	pieceSecondsLeft: number,
	device: ControlsHint.Device,
	showControls: boolean?,
	showHint: boolean?,
	-- Whether the camera is showing the whole board. Only colours the button —
	-- the camera controller owns the state.
	overview: boolean?,
	onToggleCamera: (() -> ())?,
	onSteer: ((value: number) -> ())?,
	onRotate: (() -> ())?,
	onDrop: (() -> ())?,
}

local function clock(seconds: number): string
	local whole = math.max(math.ceil(seconds), 0)
	return string.format("%d:%02d", whole // 60, whole % 60)
end

local function ordinal(rank: number): string
	if rank <= 0 then
		return "—"
	end
	local suffix = "th"
	-- 11th, 12th and 13th are the exceptions the last-digit rule gets wrong. A
	-- six-player match can't reach them, but the function shouldn't be the thing
	-- that breaks if the lane cap ever moves.
	if rank % 100 < 11 or rank % 100 > 13 then
		local last = rank % 10
		suffix = if last == 1 then "st" elseif last == 2 then "nd" elseif last == 3 then "rd" else "th"
	end
	return `{rank}{suffix}`
end

-- One row of the live standings board.
local function boardRow(entry: Entry, rank: number, you: boolean, order: number)
	return React.createElement(ui.Panel, {
		size = UDim2.new(1, 0, 0, BOARD_ROW),
		-- Your own row is the one you look for, so it's the one that's lit.
		variant = if you then "yellow" else nil,
		layoutOrder = order,
	}, {
		Row = React.createElement(ui.Row, {
			size = UDim2.fromScale(1, 1),
			gap = 6,
			padding = 6,
		}, {
			Place = React.createElement(ui.Text, {
				text = tostring(rank),
				textSize = 22,
				weight = Enum.FontWeight.Heavy,
				color = PLACE_COLORS[rank] or MUTED_COLOR,
				xAlignment = Enum.TextXAlignment.Center,
				size = UDim2.new(0, 26, 1, 0),
				layoutOrder = 1,
			}),
			Name = React.createElement(ui.Text, {
				text = entry.name,
				textSize = 20,
				weight = if you then Enum.FontWeight.Bold else Enum.FontWeight.Medium,
				color = if you then YOU_COLOR else nil,
				xAlignment = Enum.TextXAlignment.Left,
				size = UDim2.new(1, -110, 1, 0),
				layoutOrder = 2,
			}),
			Height = React.createElement(ui.Text, {
				text = string.format("%.0f", entry.height),
				textSize = 22,
				weight = Enum.FontWeight.Bold,
				xAlignment = Enum.TextXAlignment.Right,
				size = UDim2.new(0, 62, 1, 0),
				layoutOrder = 3,
			}),
		}),
	})
end

-- The live board, top right. Always MAX_LANES rows tall; the empty seats are
-- simply blank, which is what keeps it from resizing under the player's eye.
local function board(props: Props)
	local rows: { [string]: any } = {
		Title = React.createElement(ui.Text, {
			text = "STANDINGS",
			textSize = 18,
			weight = Enum.FontWeight.Heavy,
			color = MUTED_COLOR,
			xAlignment = Enum.TextXAlignment.Center,
			size = UDim2.new(1, 0, 0, BOARD_TITLE),
			layoutOrder = 0,
		}),
	}
	local userId = Players.LocalPlayer.UserId
	for rank, entry in props.standings do
		rows[`Row{rank}`] = boardRow(entry, rank, entry.userId == userId, rank)
	end

	return React.createElement(ui.Panel, {
		size = UDim2.fromOffset(BOARD_WIDTH, BOARD_HEIGHT),
		position = UDim2.new(1, -EDGE_MARGIN, 0, TOP_MARGIN),
		anchorPoint = Vector2.new(1, 0),
	}, {
		List = React.createElement(ui.Stack, {
			size = UDim2.fromScale(1, 1),
			gap = BOARD_GAP,
			padding = BOARD_PAD,
			verticalAlignment = Enum.VerticalAlignment.Top,
		}, rows),
	})
end

-- The centred moment: a countdown before the first piece, the final standings
-- after the last one. Only one is ever up, and never while anything is being
-- aimed — which is what lets both sit dead centre over the towers.
local function centrepiece(props: Props)
	if props.phase == PHASE.COUNTDOWN then
		return React.createElement(ui.Text, {
			text = tostring(math.max(math.ceil(props.secondsLeft), 1)),
			textSize = COUNTDOWN_TEXT_SIZE,
			weight = Enum.FontWeight.Heavy,
			shadow = true,
			xAlignment = Enum.TextXAlignment.Center,
			size = UDim2.fromOffset(300, 180),
			position = UDim2.fromScale(0.5, 0.5),
			anchorPoint = Vector2.new(0.5, 0.5),
		})
	end

	if props.phase ~= PHASE.RESULTS then
		return nil
	end

	local rows: { [string]: any } = {
		Title = React.createElement(ui.Text, {
			text = "FINAL HEIGHTS",
			textSize = 30,
			weight = Enum.FontWeight.Heavy,
			shadow = true,
			xAlignment = Enum.TextXAlignment.Center,
			size = UDim2.new(1, 0, 0, RESULTS_TITLE),
			layoutOrder = 0,
		}),
	}
	local userId = Players.LocalPlayer.UserId
	for rank, entry in props.standings do
		rows[`Row{rank}`] = React.createElement(ui.Row, {
			size = UDim2.new(1, 0, 0, RESULTS_ROW),
			gap = 10,
			layoutOrder = rank,
		}, {
			Place = React.createElement(ui.Text, {
				text = ordinal(rank),
				textSize = 26,
				weight = Enum.FontWeight.Heavy,
				color = PLACE_COLORS[rank] or MUTED_COLOR,
				xAlignment = Enum.TextXAlignment.Left,
				size = UDim2.new(0, 70, 1, 0),
				layoutOrder = 1,
			}),
			Name = React.createElement(ui.Text, {
				text = entry.name,
				textSize = 26,
				weight = Enum.FontWeight.Bold,
				color = if entry.userId == userId then YOU_COLOR else nil,
				xAlignment = Enum.TextXAlignment.Left,
				size = UDim2.new(1, -190, 1, 0),
				layoutOrder = 2,
			}),
			Height = React.createElement(ui.Text, {
				text = `{string.format("%.1f", entry.height)} studs`,
				textSize = 26,
				weight = Enum.FontWeight.Bold,
				xAlignment = Enum.TextXAlignment.Right,
				size = UDim2.new(0, 120, 1, 0),
				layoutOrder = 3,
			}),
		})
	end

	return React.createElement(ui.Panel, {
		size = UDim2.fromOffset(RESULTS_WIDTH, 0),
		position = UDim2.fromScale(0.5, 0.5),
		anchorPoint = Vector2.new(0.5, 0.5),
	}, {
		List = React.createElement(ui.Stack, {
			size = UDim2.new(1, 0, 0, 0),
			automaticSize = Enum.AutomaticSize.Y,
			gap = 4,
			padding = ui.theme.padding + ui.theme.strokeThickness,
		}, rows),
	})
end

return function(props: Props)
	local playing = props.myHeight ~= nil
	local canAct = props.holding and props.phase == PHASE.PLAYING

	local column: { [string]: any } = {
		Clock = React.createElement(ui.Panel, {
			size = UDim2.new(1, 0, 0, CLOCK_HEIGHT),
			layoutOrder = 1,
		}, {
			Time = React.createElement(ui.Text, {
				-- The countdown phase counts *itself* down in the centre of the
				-- screen, so the clock up here shows the match that's about to
				-- start rather than a second number racing the first.
				text = if props.phase == PHASE.COUNTDOWN
					then clock(props.matchSeconds)
					else clock(props.secondsLeft),
				textSize = CLOCK_TEXT_SIZE,
				weight = Enum.FontWeight.Heavy,
				shadow = true,
				color = if props.phase == PHASE.PLAYING and props.secondsLeft <= URGENT_SECONDS
					then URGENT_COLOR
					else nil,
				xAlignment = Enum.TextXAlignment.Center,
				size = UDim2.fromScale(1, 1),
			}),
		}),

		Stats = React.createElement(ui.Panel, {
			size = UDim2.new(1, 0, 0, STATS_HEIGHT),
			layoutOrder = 2,
		}, {
			Row = React.createElement(ui.Row, { size = UDim2.fromScale(1, 1) }, {
				Height = React.createElement(ui.Text, {
					-- A spectator has no height of their own, and "0.0 studs" would
					-- be a lie rather than an absence.
					text = if playing
						then `{string.format("%.1f", props.myHeight :: number)} studs`
						else "Watching",
					textSize = STAT_TEXT_SIZE,
					weight = Enum.FontWeight.Heavy,
					shadow = true,
					xAlignment = Enum.TextXAlignment.Center,
					size = UDim2.new(0.62, 0, 1, 0),
					layoutOrder = 1,
				}),
				Rank = React.createElement(ui.Text, {
					text = if playing then ordinal(props.myRank) else "",
					textSize = STAT_TEXT_SIZE - 4,
					weight = Enum.FontWeight.Bold,
					color = PLACE_COLORS[props.myRank] or MUTED_COLOR,
					xAlignment = Enum.TextXAlignment.Center,
					size = UDim2.new(0.38, 0, 1, 0),
					layoutOrder = 2,
				}),
			}),
		}),

		Zone = React.createElement(ui.Text, {
			text = props.zoneName,
			textSize = ZONE_TEXT_SIZE,
			weight = Enum.FontWeight.Bold,
			shadow = true,
			color = MUTED_COLOR,
			xAlignment = Enum.TextXAlignment.Center,
			size = UDim2.new(1, 0, 0, ZONE_HEIGHT),
			layoutOrder = 3,
		}),
	}

	local children: { [string]: any } = {
		Column = React.createElement(ui.Stack, {
			gap = STACK_GAP,
			size = UDim2.fromOffset(COLUMN_WIDTH, 0),
			automaticSize = Enum.AutomaticSize.Y,
			position = UDim2.new(0.5, 0, 0, TOP_MARGIN),
			anchorPoint = Vector2.new(0.5, 0),
		}, column),

		Board = board(props),

		-- Shows the whole board instead of your own lane. The same button, in the
		-- same corner, as the classic HUD's overview toggle — it answers the same
		-- question ("show me more than I'm building on"), and a player who has
		-- learned where it lives shouldn't have to learn again per mode.
		CameraToggle = React.createElement(ui.IconButton, {
			icon = ui.assets.Icons.magnifyingGlass,
			variant = if props.overview then "green" else "blue",
			size = UDim2.fromOffset(CAMERA_BUTTON, CAMERA_BUTTON),
			position = UDim2.new(1, -EDGE_MARGIN, 1, -EDGE_MARGIN),
			anchorPoint = Vector2.new(1, 1),
			onClick = props.onToggleCamera,
		}),
	}

	-- The piece being aimed, named at the bottom where the player is already
	-- looking when they're about to place. Nothing to say between pieces.
	if canAct then
		children.Status = React.createElement(ui.Text, {
			text = props.pieceName,
			textSize = ui.theme.textSizeRegular,
			weight = Enum.FontWeight.Bold,
			shadow = true,
			xAlignment = Enum.TextXAlignment.Center,
			size = UDim2.new(0, COLUMN_WIDTH, 0, ui.theme.textSizeRegular + 8),
			position = UDim2.new(
				0.5,
				0,
				1,
				-(if props.showControls then CONTROL_ROW_HEIGHT + EDGE_MARGIN * 2 else EDGE_MARGIN)
			),
			anchorPoint = Vector2.new(0.5, 1),
		})

		-- The drop clock, flanking the column rather than sitting in it — same
		-- rule as the classic dial, and for the same reason: a dial that comes and
		-- goes with every piece must not be able to resize the readout beside it.
		children.Dial = React.createElement(RadialTimer, {
			progress = math.clamp(props.pieceSecondsLeft / math.max(PvpConstants.PIECE_SECONDS, 1), 0, 1),
			label = tostring(math.max(math.ceil(props.pieceSecondsLeft), 0)),
			color = if props.pieceSecondsLeft <= DIAL_URGENT_SECONDS then DIAL_URGENT_COLOR else DIAL_COLOR,
			size = DIAL_SIZE,
			position = UDim2.new(0.5, COLUMN_WIDTH / 2 + EDGE_MARGIN + DIAL_SIZE / 2, 0, FLANK_Y),
			anchorPoint = Vector2.new(0.5, 0.5),
		})
	end

	-- Opt-out rather than opt-in, matching the classic HUD: the hint fades itself
	-- out after HINT_SECONDS, so "show it" is the right default and the flag
	-- exists for the story.
	if props.showHint ~= false then
		children.Hint = React.createElement(ControlsHint, { device = props.device })
	end

	-- Touch controls. Rendered by the view only on touch-without-keyboard devices,
	-- and greyed out rather than unmounted between pieces so the row doesn't
	-- appear and disappear under the player's thumbs.
	if props.showControls then
		children.Controls = React.createElement(ui.Row, {
			gap = CONTROL_GAP,
			size = UDim2.fromOffset(CONTROL_ROW_WIDTH, CONTROL_ROW_HEIGHT),
			position = UDim2.new(0.5, 0, 1, -EDGE_MARGIN),
			anchorPoint = Vector2.new(0.5, 1),
		}, {
			Stick = React.createElement(SteerStick, {
				disabled = not canAct,
				onSteer = props.onSteer or function() end,
				layoutOrder = 1,
			}),
			Turn = React.createElement(ui.Button, {
				text = "TURN",
				variant = "purple",
				size = BUTTON_SIZE,
				disabled = not canAct,
				onClick = props.onRotate,
				layoutOrder = 2,
			}),
			Drop = React.createElement(ui.Button, {
				text = "DROP",
				variant = "red",
				size = DROP_SIZE,
				disabled = not canAct,
				onClick = props.onDrop,
				layoutOrder = 3,
			}),
		})
	end

	children.Centre = centrepiece(props)

	return React.createElement("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, children)
end
