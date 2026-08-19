--!strict
-- The daily rewards window body: the run laid out as cards, plus a footer that
-- says when the next one opens.
--
-- Dumb by construction (see docs/game/headless-core.md) — it takes the week, the
-- resolved run state and an `onClaim`, and calls it with a day number. It
-- doesn't know a packet exists, doesn't decide what's claimable (Cycle does,
-- and the server re-decides), and doesn't run the clock (the View ticks it).
--
-- The window chrome is *not* here. The Sidebar rail renders `ui.Window` around
-- whatever `UIRegistry.registerScreen` gave it, so this returns body content
-- only — same shape as NotesUI.
--
-- Shape: the non-grand days fill a grid, and the last day is one tall card
-- beside it spanning the whole height. That asymmetry is the point — the week
-- reads as "six steps and a payoff" rather than as a uniform run of tiles, so
-- the card the player is working towards is the one the eye lands on.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ui = require(ReplicatedStorage.Shared.Boil).ui
local Constants = require(script.Parent.Constants)
local Cycle = require(script.Parent.Cycle)
local Layout = require(script.Parent.Layout)
local Registry = require(script.Parent.Registry)

local theme = ui.theme

export type Props = {
	-- One entry per day of the run; `false` where nothing registered that slot.
	days: { Registry.Day | false },
	-- Where the run stands, already resolved (Cycle.resolve).
	state: Cycle.State,
	onClaim: (day: number) -> (),
	-- Override the shipped card size — the story drives these from sliders.
	squareSize: number?,
	grandWidth: number?,
}

-- Muted copy for the grand card's second line and the footer.
local MUTED = Color3.fromRGB(196, 203, 224)
-- What a day that's out of play fades to. Panel's glass default is 0.8;
-- pushing past it sinks claimed and locked days behind the live one.
local SPENT_TRANSPARENCY = 0.9
local SPENT_ICON_TRANSPARENCY = 0.55

-- The claim button's breath, and the tween that puts it back when the day is
-- taken. RepeatCount -1 with Reverses is what makes one tween a loop: the scale
-- runs out to PULSE_SCALE, back to 1, and again, without a frame of Luau behind
-- it.
local PULSE_TWEEN = TweenInfo.new(
	Constants.PULSE_SECONDS,
	Enum.EasingStyle.Sine,
	Enum.EasingDirection.InOut,
	-1,
	true
)
local SETTLE_TWEEN = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Stand-in for a slot no feature registered. Drawn rather than skipped: a hole
-- in the week is a content bug worth seeing, and shortening the run would
-- silently renumber every day after it.
local UNREGISTERED_NAME = "???"

-- The bottom row of every card, in one of three states.
--
-- Claimed and locked are *disabled* Buttons rather than Badges. Badge hardcodes
-- left-aligned text and a leading icon slot (see Badge.luau) — it's a title
-- pill, and used as a status row it would put "Day 5" against the left edge
-- while the live "Claim" sits centered, so the column would read as two
-- different controls. Disabled Button keeps every state the same object: same
-- shape, same centered label, dimmed by the skin's own overlay, with no hover
-- feedback and no click to promise something the day can't deliver.
--
-- A component rather than a plain builder, because the live one *pulses* and a
-- pulse needs a hook. The swell is the whole reason the window opens itself at a
-- player on join (see `DailyRewardsPrompt`): a dimmed screen points at this row,
-- and a button that sits perfectly still in the middle of it is one a new player
-- reads as a label rather than a control.
local function ClaimAction(props: {
	day: number,
	status: Cycle.Status,
	-- False when the slot has no registered reward: there's nothing to hand
	-- over, so the button can't be live even on the day it comes up.
	available: boolean,
	height: number,
	textSize: number,
	layoutOrder: number,
	onClaim: (day: number) -> (),
}): any
	local live = props.status == "ready" and props.available
	local label = if live
		then "Claim"
		elseif props.status == "claimed" then "Claimed"
		else `Day {props.day}`
	local variant = if live then "green" elseif props.status == "claimed" then "white" else "red"

	-- One tween, repeating forever and reversing, is the whole animation: the
	-- scale runs 1 → PULSE_SCALE → 1 until the day is claimed, at which point the
	-- target drops back to 1 and SETTLE puts it there once. No per-frame work and
	-- nothing to tear down by hand — the hook cancels the tween when the target
	-- changes or the card unmounts.
	local scaleRef = ui.useTweenedScale(if live then Constants.PULSE_SCALE else 1, {
		tweenInfo = if live then PULSE_TWEEN else SETTLE_TWEEN,
	})

	local button = React.createElement(ui.Button, {
		variant = variant :: any,
		text = label,
		textSize = props.textSize,
		size = UDim2.fromScale(1, 1),
		disabled = not live,
		onClick = if live
			then function()
				props.onClaim(props.day)
			end
			else nil,
	})

	return React.createElement(ui.Slot, {
		size = UDim2.new(1, 0, 0, props.height),
		layoutOrder = props.layoutOrder,
	}, {
		-- The UIScale rides on an inner, centred slot: a UIScale transforms about
		-- its parent's AnchorPoint, and the row's own top-left anchor would make
		-- the button swell down and to the right instead of about itself.
		Pulse = React.createElement(ui.Slot, {
			size = UDim2.fromScale(1, 1),
			position = UDim2.fromScale(0.5, 0.5),
			anchorPoint = Vector2.new(0.5, 0.5),
		}, {
			Scale = React.createElement("UIScale", { Scale = 1, ref = scaleRef }),
			Button = button,
		}),
	})
end

-- One day, square or grand. Everything that differs between the two is a number
-- the caller passes in; the structure — day header, art, reward name, optional
-- caption, action — is shared, which is what keeps the grand card reading as
-- the same object at a different scale.
--
-- `nameOverlay` is the one structural fork. On a square card the name rides on
-- the bottom of the art the way a SidebarItem label rides on its icon, so the
-- row it would have cost goes to the picture instead — the difference between a
-- legible reward and a thumbnail.
local function rewardCard(props: {
	day: number,
	entry: Registry.Day | false,
	status: Cycle.Status,
	size: UDim2,
	iconHeight: number,
	headerTextSize: number,
	nameTextSize: number,
	nameOverlay: boolean?,
	actionHeight: number,
	rowGap: number,
	layoutOrder: number,
	onClaim: (day: number) -> (),
}): any
	local entry = props.entry
	local available = entry ~= false
	local spent = props.status ~= "ready" or not available
	local inset = Layout.inset()
	local nameHeight = props.nameTextSize + 4

	local name = if entry ~= false then entry.name else UNREGISTERED_NAME
	local icon = if entry ~= false and entry.icon ~= nil
		then entry.icon
		else ui.assets.Icons.questionMark

	local art = React.createElement("Frame", {
		Size = UDim2.new(1, 0, 0, props.iconHeight),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = 2,
	}, {
		Icon = React.createElement("ImageLabel", {
			-- Square and centered rather than full-width: the art has to read
			-- as a single object under the label, and a wide box would strand
			-- the name over empty space either side of a Fit-scaled image.
			Size = UDim2.fromOffset(props.iconHeight, props.iconHeight),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = icon,
			ImageTransparency = if spent then SPENT_ICON_TRANSPARENCY else 0,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 1,
		}),

		-- Plain text with a miter stroke rather than the offset gem shadow —
		-- the same call SidebarItem makes, and for the same reason: a drop
		-- shadow over busy icon art reads as a smudge, an outline as a cutout.
		Name = if props.nameOverlay
			then React.createElement(ui.Text, {
				text = name,
				textSize = props.nameTextSize,
				weight = Enum.FontWeight.Heavy,
				strokeThickness = theme.thinStrokeThickness,
				yAlignment = Enum.TextYAlignment.Bottom,
				size = UDim2.new(1, 0, 0, nameHeight),
				position = UDim2.fromScale(0.5, 1),
				anchorPoint = Vector2.new(0.5, 1),
				zIndex = 2,
			})
			else nil,
	})

	local caption = if entry ~= false then entry.caption else nil

	return React.createElement(ui.Panel, {
		size = props.size,
		-- A layout owns a cell's Position but not its AnchorPoint, so leaving
		-- Panel's centered default would slide every card half a tile up and
		-- left of where the grid put it.
		position = UDim2.fromScale(0, 0),
		anchorPoint = Vector2.new(0, 0),
		transparency = if spent then SPENT_TRANSPARENCY else nil,
		layoutOrder = props.layoutOrder,
	}, {
		Body = React.createElement(ui.Stack, {
			gap = props.rowGap,
			padding = inset,
			children = {
				-- The day number leads: it's what a player scans for when
				-- working out where in the week they are.
				Header = React.createElement(ui.Text, {
					text = `Day {props.day}`,
					textSize = props.headerTextSize,
					weight = Enum.FontWeight.Heavy,
					shadow = true,
					size = UDim2.new(1, 0, 0, props.headerTextSize + 4),
					layoutOrder = 1,
				}),

				Art = art,

				-- Only when the name isn't already riding on the art.
				Name = if props.nameOverlay
					then nil
					else React.createElement(ui.Text, {
						text = name,
						textSize = props.nameTextSize,
						weight = Enum.FontWeight.Heavy,
						shadow = true,
						size = UDim2.new(1, 0, 0, nameHeight),
						layoutOrder = 3,
					}),

				Caption = if caption ~= nil
					then React.createElement(ui.Text, {
						text = caption,
						textSize = theme.textSizeRegular,
						color = MUTED,
						size = UDim2.new(1, 0, 0, theme.textSizeRegular + 4),
						layoutOrder = 4,
					})
					else nil,

				Action = React.createElement(ClaimAction, {
					day = props.day,
					status = props.status,
					available = available,
					height = props.actionHeight,
					textSize = theme.textSizeRegular,
					layoutOrder = 9,
					onClaim = props.onClaim,
				}),
			},
		}),
	})
end

return function(props: Props)
	local metrics = Layout.metrics(props.squareSize, props.grandWidth)
	local state = props.state
	local grandDay = Constants.CYCLE_DAYS

	local cards: { [string]: any } = {}
	for day = 1, metrics.squares do
		cards[`Day{day}`] = rewardCard({
			day = day,
			entry = props.days[day] or false,
			status = Cycle.statusFor(day, state),
			-- UIGridLayout reasserts Size on its direct children, but pass an
			-- explicit square so Panel never falls back to its giant
			-- theme.windowSize default if the layout can't reach it.
			size = UDim2.fromOffset(
				props.squareSize or Constants.SQUARE_SIZE,
				props.squareSize or Constants.SQUARE_SIZE
			),
			iconHeight = metrics.squareIcon,
			headerTextSize = theme.textSizeRegular,
			-- A tier above the header: the reward is what the card is *for*,
			-- the day number is just its address in the week. Costs no layout —
			-- the name is overlaid, so the bigger tier eats into the art.
			nameTextSize = theme.textSizeLarge,
			nameOverlay = true,
			actionHeight = Constants.ACTION_HEIGHT,
			rowGap = Constants.CARD_ROW_GAP,
			layoutOrder = day,
			onClaim = props.onClaim,
		})
	end

	local grand = rewardCard({
		day = grandDay,
		entry = props.days[grandDay] or false,
		status = Cycle.statusFor(grandDay, state),
		size = UDim2.fromOffset(metrics.grandWidth, metrics.grandHeight),
		iconHeight = metrics.grandIcon,
		headerTextSize = theme.textSizeLarge,
		-- One tier above the squares' name; the grand prize has to keep
		-- winning the page.
		nameTextSize = theme.textSizeXL,
		actionHeight = Constants.GRAND_ACTION_HEIGHT,
		rowGap = Constants.GRAND_ROW_GAP,
		layoutOrder = 2,
		onClaim = props.onClaim,
	})

	-- Where the player stands, in words. Reads as a prompt when something is
	-- waiting and as a clock when nothing is, because those are the only two
	-- questions this screen gets asked.
	local footerText = if state.canClaim
		then `Day {state.nextDay} is ready — claim it!`
		else `Next reward in {Cycle.formatDuration(state.secondsUntilReset)}`

	return React.createElement(ui.Stack, {
		gap = theme.contentSpacing,
		size = UDim2.new(1, 0, 0, metrics.contentHeight),
		children = {
			Cards = React.createElement(ui.Row, {
				gap = Constants.CARD_GAP,
				size = UDim2.new(1, 0, 0, metrics.gridHeight),
				layoutOrder = 1,
				children = {
					Grid = React.createElement(ui.Grid, {
						cellSize = UDim2.fromOffset(
							props.squareSize or Constants.SQUARE_SIZE,
							props.squareSize or Constants.SQUARE_SIZE
						),
						cellPadding = UDim2.fromOffset(Constants.CARD_GAP, Constants.CARD_GAP),
						fillDirectionMaxCells = Constants.COLUMNS,
						size = UDim2.fromOffset(metrics.gridWidth, metrics.gridHeight),
						layoutOrder = 1,
						children = cards,
					}),
					Grand = grand,
				},
			}),

			Footer = React.createElement(ui.Text, {
				text = footerText,
				textSize = theme.textSizeLarge,
				weight = Enum.FontWeight.Heavy,
				color = if state.canClaim then nil else MUTED,
				shadow = true,
				size = UDim2.new(1, 0, 0, Constants.FOOTER_HEIGHT),
				layoutOrder = 2,
			}),
		},
	})
end
