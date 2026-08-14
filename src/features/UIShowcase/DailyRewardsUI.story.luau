--!nonstrict
-- Daily login rewards frame — a story-only prototype (see docs/game/UIShowcase.md).
--
-- Seven days: six square cards in a 3x2 grid, then one tall grand-prize card
-- spanning both rows on the right. The asymmetry is the point — the week reads
-- as "six steps and a payoff" rather than as a uniform run of eight tiles, so
-- the last card is the one the eye lands on.
--
-- Every card is the same function; only its box and its type sizes differ. A
-- card's *state* comes from one place (`statusFor`), so the grid can't disagree
-- with the grand card about which day is claimable.
--
-- Geometry flows outward: the square size and the grand card's width are the
-- two inputs, and the window sizes itself to whatever they add up to. Drag the
-- sliders and the chrome follows instead of clipping.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local UILabs = require(ReplicatedStorage.Packages.UILabs)
local ui = require(ReplicatedStorage.Shared.Boil).ui

local theme = ui.theme

local COLUMNS = 3
local ROWS = 2
local SQUARE_DAYS = COLUMNS * ROWS
local TOTAL_DAYS = SQUARE_DAYS + 1

-- Gap between rows *inside* a card. Deliberately smaller than the gap between
-- cards (theme.contentSpacing): a card's four rows are one object, and spacing
-- them as far apart as two neighbouring cards would dissolve it.
local CARD_ROW_GAP = 6
local GRAND_ROW_GAP = 10

-- Muted copy for the secondary line on the grand card.
local MUTED = Color3.fromRGB(196, 203, 224)
-- What a card that's out of play fades to. Panel's glass default is 0.8;
-- pushing past it sinks claimed and locked days behind today's.
local SPENT_TRANSPARENCY = 0.9
local SPENT_ICON_TRANSPARENCY = 0.55

-- The week. Names are short on purpose: they sit on the body floor
-- (textSizeRegular) inside a ~180px card, so "Backpack" fits and
-- "Legendary Backpack" would need a text size no phone can read.
local REWARDS = {
	{ name = "100 Cash", icon = ui.assets.Icons.bandOfCash },
	{ name = "Free Spin", icon = ui.assets.Icons.wheel },
	{ name = "250 Cash", icon = ui.assets.Icons.bandOfCash },
	{ name = "Rocket", icon = ui.assets.Icons.rocket },
	{ name = "Mystery", icon = ui.assets.Icons.questionMark },
	{ name = "Backpack", icon = ui.assets.Icons.backpack },
	-- Day 7 — the grand prize.
	{ name = "Rebirth", icon = ui.assets.Icons.rebirth, caption = "Grand prize" },
}

-- One source of truth for which day is which. Both the grid and the grand card
-- read this, so they can't end up disagreeing about what's claimable.
local function statusFor(day: number, currentDay: number, claimedToday: boolean): string
	if day < currentDay then
		return "claimed"
	end
	if day > currentDay then
		return "locked"
	end
	return if claimedToday then "claimed" else "ready"
end

-- The bottom row: one Button per card, in one of three states.
--
-- A claimed or locked day is a *disabled* Button rather than a Badge. Badge
-- hardcodes left-aligned text and a leading icon slot (see Badge.luau) — it's a
-- title pill, and used as a status row it puts "Day 5" against the left edge
-- while the live "Claim" sits centered, so the column reads as two different
-- controls. Disabled Button keeps every state the same object: same shape, same
-- centered label, dimmed by the skin's own overlay, with no hover feedback and
-- no click to promise something the day can't deliver.
local function actionFor(day: number, status: string, height: number, textSize: number): any
	local label = if status == "ready"
		then "Claim"
		elseif status == "claimed" then "Claimed"
		else `Day {day}`
	local variant = if status == "ready" then "green" elseif status == "claimed" then "white" else "red"

	return React.createElement(ui.Button, {
		variant = variant,
		text = label,
		textSize = textSize,
		size = UDim2.new(1, 0, 0, height),
		layoutOrder = 9,
		disabled = status ~= "ready",
		onClick = if status == "ready"
			then function()
				print(`[DailyRewardsUI.story] claim day {day}`)
			end
			else nil,
	})
end

-- One reward card, square or grand. Everything that differs between the two is
-- a number the caller passes in; the structure — day header, art, reward name,
-- optional caption, action — is shared, which is what keeps the grand card
-- reading as the same object at a different scale.
--
-- `nameOverlay` is the one structural fork. On a square card the name rides on
-- the bottom of the art the way a SidebarItem's label rides on its icon: the
-- row it would have taken goes to the picture instead, which is the difference
-- between a legible reward and a 46px thumbnail. The grand card has the height
-- to give the name its own line, so it does.
local function rewardCard(props: {
	day: number,
	reward: { name: string, icon: string, caption: string? },
	status: string,
	size: UDim2,
	-- Height of the art slot, worked out by the caller from the box it has.
	iconHeight: number,
	headerHeight: number,
	headerTextSize: number,
	nameTextSize: number,
	nameOverlay: boolean?,
	actionHeight: number,
	actionTextSize: number,
	rowGap: number,
	layoutOrder: number,
}): any
	local spent = props.status ~= "ready"
	-- Stroke sits inside the panel edge, so pad past it (see CLAUDE.md).
	local inset = theme.padding + theme.strokeThickness
	local nameHeight = props.nameTextSize + 4

	local icon = React.createElement("ImageLabel", {
		-- Square and centered rather than full-width: the art has to read as a
		-- single object under the label, and a wide box would strand the name
		-- over empty space either side of a Fit-scaled image.
		Size = UDim2.fromOffset(props.iconHeight, props.iconHeight),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = props.reward.icon,
		ImageTransparency = if spent then SPENT_ICON_TRANSPARENCY else 0,
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = 1,
	})

	-- The name, drawn over the bottom of the art. Plain text with a miter
	-- stroke rather than the offset gem shadow — the same call SidebarItem
	-- makes, and for the same reason: a drop shadow over busy icon art reads
	-- as a smudge, an outline reads as a cutout.
	local overlaidName = React.createElement(ui.Text, {
		text = props.reward.name,
		textSize = props.nameTextSize,
		weight = Enum.FontWeight.Heavy,
		strokeThickness = theme.thinStrokeThickness,
		yAlignment = Enum.TextYAlignment.Bottom,
		size = UDim2.new(1, 0, 0, nameHeight),
		position = UDim2.fromScale(0.5, 1),
		anchorPoint = Vector2.new(0.5, 1),
		zIndex = 2,
	})

	-- Art slot: just the picture on the grand card, picture + overlaid name on
	-- a square one.
	local art = React.createElement("Frame", {
		Size = UDim2.new(1, 0, 0, props.iconHeight),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = 2,
	}, {
		Icon = icon,
		Name = if props.nameOverlay then overlaidName else nil,
	})

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
					size = UDim2.new(1, 0, 0, props.headerHeight),
					layoutOrder = 1,
				}),

				Art = art,

				-- Only when the name isn't already riding on the art.
				Name = if props.nameOverlay
					then nil
					else React.createElement(ui.Text, {
						text = props.reward.name,
						textSize = props.nameTextSize,
						weight = Enum.FontWeight.Heavy,
						shadow = true,
						size = UDim2.new(1, 0, 0, nameHeight),
						layoutOrder = 3,
					}),

				Caption = if props.reward.caption ~= nil
					then React.createElement(ui.Text, {
						text = props.reward.caption,
						textSize = theme.textSizeRegular,
						color = MUTED,
						size = UDim2.new(1, 0, 0, theme.textSizeRegular + 4),
						layoutOrder = 4,
					})
					else nil,

				Action = actionFor(props.day, props.status, props.actionHeight, props.actionTextSize),
			},
		}),
	})
end

return {
	summary = "Daily login rewards — six square days in a 3x2 grid plus a tall day-7 grand prize. "
		.. "`currentDay` moves the claimable card; `claimedToday` flips it to Claimed. "
		.. "The window sizes itself from the card sliders.",
	react = React,
	reactRoblox = ReactRoblox,

	controls = {
		currentDay = UILabs.Slider(1, 1, TOTAL_DAYS, 1),
		claimedToday = false,
		-- The default is the smallest square that still leaves the art a
		-- three-figure height once the header and the action have taken their
		-- rows. Drag it down and the picture is the first thing to suffer.
		squareSize = UILabs.Slider(240, 150, 300, 5),
		grandWidth = UILabs.Slider(320, 200, 440, 5),
	},

	story = function(props)
		local c = props.controls

		-- One spacing value drives the gap between cards *and* the inset from
		-- the window edge, so the border around the grid reads identical to the
		-- gutter inside it. Pulled from the theme so a live edit in the Theme
		-- story flows through here.
		local gap = theme.contentSpacing
		local inset = theme.padding + theme.strokeThickness

		local square = c.squareSize
		local gridWidth = square * COLUMNS + gap * (COLUMNS - 1)
		local gridHeight = square * ROWS + gap * (ROWS - 1)

		-- Square card body: header, art, action, two gaps — the name costs no
		-- row of its own, it sits on the art. The art gets whatever the other
		-- two rows leave, so shrinking the card squeezes the picture rather
		-- than dropping text below the readability floor.
		local squareHeader = theme.textSizeRegular + 4
		local squareAction = 46
		local squareIcon =
			math.max(24, square - inset * 2 - (squareHeader + squareAction + CARD_ROW_GAP * 2))

		local cards: { [string]: any } = {}
		for day = 1, SQUARE_DAYS do
			cards[`Day{day}`] = rewardCard({
				day = day,
				reward = REWARDS[day],
				status = statusFor(day, c.currentDay, c.claimedToday),
				-- UIGridLayout reasserts Size on its direct children, but pass
				-- an explicit square so Panel never falls back to its
				-- theme.windowSize default if the layout can't reach it.
				size = UDim2.fromOffset(square, square),
				iconHeight = squareIcon,
				headerHeight = squareHeader,
				headerTextSize = theme.textSizeRegular,
				-- A tier above the header: the reward is what the card is
				-- *for*, and the day number is just its address in the week.
				-- Costs no layout — the name is overlaid, so a bigger tier
				-- eats into the art rather than into a row of its own.
				nameTextSize = theme.textSizeLarge,
				nameOverlay = true,
				actionHeight = squareAction,
				actionTextSize = theme.textSizeRegular,
				rowGap = CARD_ROW_GAP,
				layoutOrder = day,
			})
		end

		-- Grand card: same rows, one tier up, plus the caption line. Its height
		-- is the grid's, which is what makes the two blocks read as one frame
		-- rather than as a panel with something bolted beside it.
		local grandHeader = theme.textSizeLarge + 6
		local grandAction = 56
		local grandIcon = math.max(
			32,
			gridHeight
				- inset * 2
				- (
					grandHeader
					-- Name row, at the tier rewardCard draws it below.
					+ (theme.textSizeXL + 4)
					+ (theme.textSizeRegular + 4)
					+ grandAction
					+ GRAND_ROW_GAP * 4
				)
		)

		local grand = rewardCard({
			day = TOTAL_DAYS,
			reward = REWARDS[TOTAL_DAYS],
			status = statusFor(TOTAL_DAYS, c.currentDay, c.claimedToday),
			size = UDim2.fromOffset(c.grandWidth, gridHeight),
			iconHeight = grandIcon,
			headerHeight = grandHeader,
			headerTextSize = theme.textSizeLarge,
			-- Stays one tier above the square cards' name, which just moved up
			-- to Large. The grand prize has to keep winning the page.
			nameTextSize = theme.textSizeXL,
			actionHeight = grandAction,
			actionTextSize = theme.textSizeRegular,
			rowGap = GRAND_ROW_GAP,
			layoutOrder = 2,
		})

		-- Grid and grand card side by side. Mounted as Window's single content
		-- child, so Window's own vertical list treats the pair as one row.
		local body = React.createElement(ui.Row, {
			gap = gap,
			size = UDim2.new(1, 0, 0, gridHeight),
			children = {
				Grid = React.createElement(ui.Grid, {
					cellSize = UDim2.fromOffset(square, square),
					cellPadding = UDim2.fromOffset(gap, gap),
					fillDirectionMaxCells = COLUMNS,
					size = UDim2.fromOffset(gridWidth, gridHeight),
					layoutOrder = 1,
					children = cards,
				}),
				Grand = grand,
			},
		})

		-- Where the player is in the week, in the top bar. Sits on the body
		-- floor: it's state a player reads, not decoration.
		local streak = React.createElement(ui.Text, {
			text = `Day {c.currentDay} of {TOTAL_DAYS}`,
			textSize = theme.textSizeLarge,
			weight = Enum.FontWeight.Heavy,
			xAlignment = Enum.TextXAlignment.Right,
			size = UDim2.new(1, -theme.padding, 1, 0),
			shadow = true,
		})

		local windowWidth = gridWidth + gap + c.grandWidth + inset * 2
		local windowHeight = gridHeight + inset * 2 + theme.topBarHeight

		return React.createElement(ui.Window, {
			size = UDim2.fromOffset(windowWidth, windowHeight),
			title = "Daily Rewards",
			icon = ui.assets.Icons.bandOfCash,
			titleVariant = "yellow",
			-- All four insets match the gutter between cards, so the frame
			-- reads as evenly spaced all the way around.
			contentPadding = { top = inset, bottom = inset, left = inset, right = inset },
			topBarExtra = streak,
			-- Widened with the tier bump so the counter can't collide with the
			-- title badge's text at the longest day number.
			topBarExtraSize = UDim2.new(0, 320, 1, 0),
			position = UDim2.fromScale(0.5, 0.5),
			anchorPoint = Vector2.new(0.5, 0.5),
			onClose = function()
				print("[DailyRewardsUI.story] close")
			end,
			children = { Body = body },
		})
	end,
}
