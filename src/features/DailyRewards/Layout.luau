--!strict
-- Where the geometry is worked out, once.
--
-- Three callers need the same arithmetic and must not disagree: the UI draws
-- the cards, the story drives them from sliders, and `Sidebar.luau` has to
-- declare a `windowSize` big enough to hold them — a rail entry that guessed
-- would clip the grid or leave a moat around it.
--
-- Everything derives from Constants and the live theme, so a card size or a
-- theme edit moves the window with it instead of desynchronising.
--
-- Sizes are plain pixel offsets against the 1280x720 reference; the root
-- ScaleLayer fits them to the viewport (see docs/game/layout-surfaces.md).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ui = require(ReplicatedStorage.Shared.Boil).ui
local Constants = require(ReplicatedStorage.Features.DailyRewards.Constants)

export type Metrics = {
	-- Non-grand days: how many, and the grid that holds them.
	squares: number,
	rows: number,
	gridWidth: number,
	gridHeight: number,
	-- Art slot inside a square card, after the header and the action row.
	squareIcon: number,
	-- The grand card spans the grid's full height.
	grandWidth: number,
	grandHeight: number,
	grandIcon: number,
	-- Cards + footer.
	contentWidth: number,
	contentHeight: number,
}

local Layout = {}

-- Both card types pad past the panel stroke (see CLAUDE.md § stroke thickness).
function Layout.inset(): number
	return ui.theme.padding + ui.theme.strokeThickness
end

function Layout.metrics(squareSize: number?, grandWidth: number?): Metrics
	local theme = ui.theme
	local square = squareSize or Constants.SQUARE_SIZE
	local grand = grandWidth or Constants.GRAND_WIDTH
	local gap = Constants.CARD_GAP
	local inset = Layout.inset()

	local squares = math.max(Constants.CYCLE_DAYS - 1, 0)
	local rows = math.max(math.ceil(squares / Constants.COLUMNS), 1)
	local gridWidth = square * Constants.COLUMNS + gap * (Constants.COLUMNS - 1)
	local gridHeight = square * rows + gap * (rows - 1)

	-- The art gets whatever the header and the action row leave. Sized this way
	-- round on purpose: shrinking a card squeezes the picture rather than
	-- dropping a label below the readability floor.
	local squareHeader = theme.textSizeRegular + 4
	local squareIcon = math.max(
		24,
		square - inset * 2 - (squareHeader + Constants.ACTION_HEIGHT + Constants.CARD_ROW_GAP * 2)
	)

	-- The grand card carries a name and a caption of its own, so its art is
	-- what's left after four rows rather than two.
	local grandRows = (theme.textSizeLarge + 6)
		+ (theme.textSizeXL + 4)
		+ (theme.textSizeRegular + 4)
		+ Constants.GRAND_ACTION_HEIGHT
		+ Constants.GRAND_ROW_GAP * 4
	local grandIcon = math.max(32, gridHeight - inset * 2 - grandRows)

	return {
		squares = squares,
		rows = rows,
		gridWidth = gridWidth,
		gridHeight = gridHeight,
		squareIcon = squareIcon,
		grandWidth = grand,
		grandHeight = gridHeight,
		grandIcon = grandIcon,
		contentWidth = gridWidth + gap + grand,
		contentHeight = gridHeight + theme.contentSpacing + Constants.FOOTER_HEIGHT,
	}
end

-- The window the rail has to open for this content to fit.
--
-- Matches ui.Window's own padding math rather than assuming it's square: the
-- top clears the panel stroke (`padding + strokeThickness`) and the other three
-- sides are the bare padding. Getting this wrong shows up as a scrollbar on a
-- window that should never scroll.
function Layout.windowSize(): UDim2
	local theme = ui.theme
	local m = Layout.metrics()
	return UDim2.fromOffset(
		m.contentWidth + theme.padding * 2,
		theme.topBarHeight + (theme.padding + theme.strokeThickness) + m.contentHeight + theme.padding
	)
end

return Layout
