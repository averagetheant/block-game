--!strict
-- Pure/dumb HUD for TowerGame. Takes the whole game state as props and renders
-- it; owns no data fetching, no networking, no clock. TowerView wires it to the
-- controller store, and TowerHUD.story drives it from sliders in UI Labs.
--
-- Layout note: this is a full-screen gameplay HUD, not a window, so it hugs the
-- edges rather than following the centered-by-default rule for feature UIs.
-- Centering a height readout would sit it on top of the tower being aimed at.
--
--   top center     turn strip → storm clock
--   flanking those  Extend Storm (left) and the turn dial (right)
--   right edge     the climb, as a vertical rail; the height rides its marker
--   bottom left    controls hint (fades out on its own)
--   bottom center  touch controls (touch devices only)
--
-- The top column flows through one Stack rather than being positioned by hand,
-- so a row appearing or disappearing reflows the rest instead of leaving a hole.
--
-- The column is deliberately thin — a strip of headshots and one line of clock.
-- Height used to sit up here in a panel of its own alongside a best-ever
-- reading, which put three stacked surfaces over the tower on a phone. The
-- height now travels with the marker on the rail (one fact, one object) and the
-- best-ever reading is gone: it's a number the player can't act on mid-drop.
--
-- The two things flanking the turn strip are the exception to the column, and
-- deliberately so: they sit *outside* it at a computed y (FLANK_Y) rather than
-- inside. The turn dial used to be laid out beside the stats panel, which meant
-- the panel had to shrink to make room and the whole readout resized and slid
-- sideways twice a turn. Nothing that comes and goes each turn should be able to
-- move the things that don't.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Boil = require(ReplicatedStorage.Shared.Boil)
local ui = Boil.ui
local audio = Boil.audio
local CashFly = require(script.Parent.CashFly)
local CheckpointQuest = require(script.Parent.CheckpointQuest)
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
-- The status line names who is placing what; it's read mid-round at a glance,
-- so it holds the body floor and its row is sized from the tier.
local STATUS_TEXT_SIZE = ui.theme.textSizeRegular
local STATUS_HEIGHT = STATUS_TEXT_SIZE + 8
local TOP_MARGIN = 10
local STACK_GAP = 6

local BUTTON_SIZE = UDim2.fromOffset(110, 88)
local DROP_SIZE = UDim2.fromOffset(160, 88)
local CONTROL_GAP = 12
-- Shared with anything else pinned to an edge (the spectator badge), so the HUD
-- and its neighbours can't disagree about where the screen ends.
local EDGE_MARGIN = Constants.EDGE_MARGIN
local CONTROL_ROW_HEIGHT = 88
-- The steering stick, then TURN and DROP, with a double gap between the stick
-- and the buttons.
local CONTROL_ROW_WIDTH = Constants.STICK_TRACK_WIDTH + 110 + 160 + CONTROL_GAP * 4

local STORM_LABEL_TEXT_SIZE = ui.theme.textSizeRegular
local STORM_LABEL_HEIGHT = STORM_LABEL_TEXT_SIZE + 8
-- The camera toggle, sitting above the cash panel on the right edge.
local CAMERA_BUTTON = 62
-- Extend Storm. Matched to CAMERA_BUTTON rather than given its own size: they
-- are the HUD's two icon buttons and reading as a pair is the point.
local EXTEND_BUTTON = CAMERA_BUTTON
-- What TurnStrip sizes itself to (`AVATAR_SIZE + 8`, see TurnStrip.ui.luau).
-- Needed here to centre the two things flanking the strip on it — derived from
-- the same expression rather than hardcoded, so a bigger avatar moves all three.
local TURN_STRIP_HEIGHT = Constants.AVATAR_SIZE + 8
-- The turn dial. Was the stats row's height back when it flanked that row, and
-- kept at the same value now that it flanks the strip — it reads as a chip
-- among the headshots at this size, and the seconds label needs the room.
local DIAL_SIZE = 66
-- Where the two things that flank the top row sit vertically: Extend Storm on
-- the left, the turn dial on the right. Walks the column's own stack — top
-- margin, then half the turn strip — so a taller avatar carries both with it.
local FLANK_Y = TOP_MARGIN + TURN_STRIP_HEIGHT / 2

local CASH_WIDTH = 205
local CASH_HEIGHT = 58
local CASH_TEXT_SIZE = 32
local CASH_ICON = 34

-- The climb, as a vertical rail down the right side of the screen.
--
-- Right rather than left: the left edge is the sidebar rail (navigation) and
-- the controls hint. Inset from the edge rather than flush to it because the
-- reactions column opens down that edge vertically centred — ~66 units of it —
-- and the two would sit on top of each other. Hardcoded rather than read from
-- that feature's constants: a feature can't name another feature, and the rail
-- only needs to be clear of it, not glued to it.
local RAIL_WIDTH = 24
local RAIL_RIGHT = 96
-- Clear of Roblox's own topbar, which owns the top strip at the true top of the
-- display (the root ScreenGui sets IgnoreGuiInset, so y = 0 really is the top).
local RAIL_TOP = 84
-- Clear of the camera toggle and the cash counter stacked in the corner below.
local RAIL_BOTTOM = CASH_HEIGHT + CAMERA_BUTTON + EDGE_MARGIN * 3
local WARNING_WIDTH = 460
-- Sized from its contents: title row + gap + detail row + the Stack's padding
-- on both sides. Grows if either text tier does.
local WARNING_TITLE_ROW = 54
local WARNING_DETAIL_ROW = 40
local WARNING_GAP = 2
local WARNING_PAD = 8
local WARNING_HEIGHT = WARNING_TITLE_ROW + WARNING_GAP + WARNING_DETAIL_ROW + WARNING_PAD * 2

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
	blockCount: number,
	phase: number,
	isMyTurn: boolean,
	-- Display name of whoever holds the piece; nil when nobody does.
	holderName: string?,
	holderUserId: number,
	-- Turn order as user ids, current holder first.
	order: { number },
	-- Who takes the next piece as well as this one (Double Turn); 0 for nobody.
	repeatUserId: number?,
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
	-- Whether to show the first-checkpoint quest line under the countdown. True
	-- for a player who has never seen a checkpoint clear (and for a few seconds
	-- after, while it shows what they won); the profile flag behind it is what
	-- makes this a new-player line rather than permanent furniture.
	showCheckpointQuest: boolean?,
	-- Flips the line from promising the prize to naming it. TowerView raises this
	-- on the replica saying the grant landed, so the line can't congratulate a
	-- player for something the server hasn't actually handed over.
	questClaimed: boolean?,
	questRewardName: string?,
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
	-- Prompts the Extend Storm purchase. Optional: the story renders the HUD
	-- without one, and so does a build with the actions presentation switched
	-- off — no handler, no button.
	onExtendStorm: (() -> ())?,
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

	-- The last five seconds of a turn tick audibly. Keyed on the whole second
	-- rather than on the raw countdown, which changes every frame — and latched,
	-- so a re-render inside the same second doesn't double up.
	--
	-- The latch is cleared whenever the countdown is outside the window, which
	-- is what re-arms it for the next turn without needing to watch for the turn
	-- itself changing.
	local secondsWhole = math.ceil(props.secondsLeft)
	local tickedAt = React.useRef(nil :: number?)
	React.useEffect(function()
		if not aiming or secondsWhole > URGENT_SECONDS or secondsWhole <= 0 then
			tickedAt.current = nil
			return
		end
		if tickedAt.current == secondsWhole then
			return
		end
		tickedAt.current = secondsWhole
		audio.playUI("tick")
	end, { secondsWhole, aiming } :: { any })

	local column: { [string]: any } = {
		Turns = React.createElement(TurnStrip, {
			order = props.order,
			holderUserId = props.holderUserId,
			repeatUserId = props.repeatUserId or 0,
			layoutOrder = 1,
		}),
	}

	-- Gone during the round break, storm clock and rail alike. The round is over,
	-- the tower they measured is wreckage, and the server has frozen
	-- `stormEndsAt` — but the client draws the clock as `stormEndsAt - now`, so
	-- leaving it up counts a dead deadline down behind the gamemode vote and then
	-- snaps back when the next round starts. Nothing to show is the honest answer.
	local stormRunning = props.phase ~= PHASE.GAMEOVER
	if stormRunning then
		column.Countdown = React.createElement(ui.Text, {
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
		})

		-- The first-checkpoint quest, directly under the countdown: that clock is
		-- the deadline for the climb and this is what the climb is worth, so the
		-- two belong in the same block of text. It inherits the countdown's rule
		-- and goes during the round break along with everything else measuring a
		-- dead run.
		--
		-- The coins are named on the claimed side only. Two standing gold promises
		-- compete rather than add up, and the skin is the one a new player can
		-- picture; the coins they can already see flying into the counter.
		if props.showCheckpointQuest then
			column.Quest = React.createElement(CheckpointQuest, {
				rewardName = props.questRewardName or "A rare skin",
				rewardExtra = `+{Constants.CASH_PER_ZONE} Coins`,
				claimed = props.questClaimed,
				layoutOrder = 3,
			})
		end
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

	-- The climb to the next checkpoint, as a rail up the right side: it measures
	-- this leg only, so every zone starts at the bottom dot. The height readout
	-- rides the marker (see ProgressLine) rather than sitting in the top column —
	-- how high the tower is and how far that is through the stage are the same
	-- question, and they're now answered in one place instead of two.
	if stormRunning then
		children.Climb = React.createElement(ProgressLine, {
			from = props.zoneBaseHeight,
			current = props.height,
			to = props.targetHeight,
			label = `{string.format("%.1f", props.height)} studs`,
			size = UDim2.new(0, RAIL_WIDTH, 1, -(RAIL_TOP + RAIL_BOTTOM)),
			position = UDim2.new(1, -RAIL_RIGHT, 0, RAIL_TOP),
			anchorPoint = Vector2.new(1, 0),
		})
	end

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

	-- Immediately left of the turn strip and vertically centred on it, rather
	-- than out at the screen edge. It buys time on the clock this column is
	-- about, so it sits beside the row it changes — and the left edge is
	-- already taken twice over, by the sidebar rail (centred) and the controls
	-- hint (bottom).
	--
	-- The y offset walks the column's own stack: top margin, then half the turn
	-- strip. Derived rather than measured, so a taller avatar carries the button
	-- with it.
	--
	-- The x offset clears the whole column width, not the strip's — the strip is
	-- narrower than the column it sits in, and pinning the button to the column
	-- keeps it still while headshots come and go either side of the holder.
	--
	-- Hidden during the round break for the same reason the storm clock is: the
	-- clock is frozen and the tower it was counting down to is wreckage, so
	-- there is nothing to extend. Offering it there would be selling a minute of
	-- a stage that no longer exists.
	if props.onExtendStorm and stormRunning then
		children.ExtendStorm = React.createElement(ui.IconButton, {
			icon = Constants.EXTEND_STORM_ICON,
			variant = "yellow",
			size = UDim2.fromOffset(EXTEND_BUTTON, EXTEND_BUTTON),
			position = UDim2.new(0.5, -(COLUMN_WIDTH / 2 + EDGE_MARGIN), 0, FLANK_Y),
			anchorPoint = Vector2.new(1, 0.5),
			onClick = props.onExtendStorm,
		})
	end

	-- The turn dial, flanking the turn strip on the right exactly as Extend
	-- Storm flanks it on the left — same y, same margin, mirrored anchor.
	--
	-- Outside the column and absolutely positioned, which is the whole point:
	-- laid out in a row it took space from the readout beside it, which resized
	-- and slid sideways every time a turn started and ended. Nothing moves now;
	-- the dial simply appears in the gap that was always there.
	if aiming then
		children.Timer = React.createElement(RadialTimer, {
			progress = props.secondsLeft / math.max(props.turnSeconds, 1),
			color = if props.secondsLeft <= URGENT_SECONDS
				then Color3.fromRGB(232, 96, 96)
				else Color3.fromRGB(112, 214, 122),
			size = DIAL_SIZE,
			label = tostring(math.ceil(props.secondsLeft)),
			position = UDim2.new(0.5, COLUMN_WIDTH / 2 + EDGE_MARGIN + DIAL_SIZE / 2, 0, FLANK_Y),
		})
	end

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
			Stack = React.createElement(ui.Stack, { gap = WARNING_GAP, padding = WARNING_PAD }, {
				Title = React.createElement(ui.Text, {
					text = props.zoneWarning.name,
					textSize = ui.theme.textSizeLarge,
					weight = Enum.FontWeight.Heavy,
					shadow = true,
					color = props.zoneWarning.tint,
					xAlignment = Enum.TextXAlignment.Center,
					size = UDim2.new(1, 0, 0, WARNING_TITLE_ROW),
					layoutOrder = 1,
				}),
				Detail = React.createElement(ui.Text, {
					text = props.zoneWarning.warning or "",
					textSize = ui.theme.textSizeRegular,
					weight = Enum.FontWeight.Bold,
					shadow = true,
					xAlignment = Enum.TextXAlignment.Center,
					size = UDim2.new(1, 0, 0, WARNING_DETAIL_ROW),
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
