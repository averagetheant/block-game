--!strict
-- The reaction bar: a white pill down the right edge of the screen, vertically
-- centred, holding one button per slot, with a small arrow tab that slides it
-- in and out. Closed on mount unless the caller says otherwise — it's a
-- garnish, and on a screen where edge space is scarce a garnish shouldn't be
-- occupying it before anyone asks. ReactionsView is what decides.
--
-- It hides sideways rather than downward, which is why the tab is on its left
-- edge: the axis the buttons are stacked on and the axis the bar travels on
-- have to be different, or the bar would slide out through its own buttons and
-- the tab would end up on top of the slot nearest the corner.
--
-- Why this doesn't use `ui.Panel` / `ui.Button`: the bar is deliberately *not*
-- the gem look. It's the one flat white surface in the game, which is what
-- makes it read as a chat affordance rather than another piece of HUD. The
-- shared kit has no neutral surface primitive and adding one would be a skin
-- contract change for a single call site — so the raw Frames stay here, with
-- every colour and radius named in Constants rather than inlined.
--
-- Dumb: it takes the slot ids and a callback. ReactionsView owns the data.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ui = require(ReplicatedStorage.Shared.Boil).ui
local Constants = require(script.Parent.Constants)
local ReactionGlyph = require(script.Parent.ReactionGlyph)

type Props = {
	-- One reaction id per slot, in bar order.
	slots: { string },
	onSend: (reactionId: string) -> (),
	-- Start open instead of closed. Read on mount only — the tab owns the state
	-- from then on. ReactionsView passes true for keyboard players; the story
	-- drives it from a control.
	initialOpen: boolean?,
}

local BUTTON = Constants.BUTTON_SIZE
local GAP = Constants.BUTTON_GAP
local PAD = Constants.BAR_PADDING
local HANDLE_W = Constants.HANDLE_WIDTH

-- The column grows along its stacking axis, which is now the vertical one.
local function barHeight(count: number): number
	return count * BUTTON + math.max(count - 1, 0) * GAP + PAD * 2
end

local BAR_WIDTH = BUTTON + PAD * 2

-- One reaction button. Its own component so the hover state doesn't re-render
-- the whole bar every time the pointer crosses a slot.
local function SlotButton(props: {
	reactionId: string,
	layoutOrder: number,
	onClick: () -> (),
})
	local hover = ui.useHoverScale()
	local hovered, setHovered = React.useState(false)

	return React.createElement("TextButton", {
		Size = UDim2.fromOffset(BUTTON, BUTTON),
		BackgroundColor3 = if hovered then Constants.BUTTON_HOVER_COLOR else Constants.BUTTON_COLOR,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = props.layoutOrder,
		[React.Event.MouseEnter] = function()
			setHovered(true)
			hover.onEnter()
		end,
		[React.Event.MouseLeave] = function()
			setHovered(false)
			hover.onLeave()
		end,
		[React.Event.MouseButton1Down] = hover.onPress,
		[React.Event.MouseButton1Up] = hover.onRelease,
		[React.Event.Activated] = props.onClick,
	}, {
		UICorner = React.createElement("UICorner", {
			CornerRadius = UDim.new(0, Constants.BUTTON_CORNER),
		}),
		UIScale = React.createElement("UIScale", {
			Scale = 1,
			ref = hover.scaleRef,
		}),
		Glyph = React.createElement(ReactionGlyph, {
			reactionId = props.reactionId,
			textSize = Constants.GLYPH_TEXT_SIZE,
		}),
	})
end

return function(props: Props)
	local open, setOpen = React.useState(props.initialOpen == true)

	local height = barHeight(#props.slots)

	-- Open: the column's right edge is flush with the right of the screen.
	-- Closed: it slides out to the right until only the handle is left poking
	-- back in. Both are anchored at the bar's left edge, vertically centred, so
	-- the column stays centred however many slots it holds and only x moves —
	-- and the handle, which hangs off the left edge, is the part that stays on
	-- screen either way.
	local openPosition = UDim2.new(1, -BAR_WIDTH, 0.5, 0)
	local closedPosition = UDim2.new(1, 0, 0.5, 0)
	local positionRef = ui.useTweenedUDim2(if open then openPosition else closedPosition, {
		tweenInfo = Constants.SLIDE_TWEEN_INFO,
	})

	local buttons: { [string]: any } = {}
	for index, reactionId in props.slots do
		buttons[`Slot{index}`] = React.createElement(SlotButton, {
			reactionId = reactionId,
			layoutOrder = index,
			onClick = function()
				props.onSend(reactionId)
			end,
		})
	end

	return React.createElement("Frame", {
		Size = UDim2.fromOffset(BAR_WIDTH, height),
		-- Rendered at the closed position and then owned by the tween; see
		-- useTweenedUDim2's note on not re-applying the prop.
		Position = if props.initialOpen then openPosition else closedPosition,
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Constants.BAR_COLOR,
		BackgroundTransparency = Constants.BAR_TRANSPARENCY,
		BorderSizePixel = 0,
		ref = positionRef,
	}, {
		UICorner = React.createElement("UICorner", {
			CornerRadius = UDim.new(0, Constants.BAR_CORNER),
		}),
		UIStroke = React.createElement("UIStroke", {
			Color = Constants.OUTLINE_COLOR,
			Thickness = Constants.OUTLINE_THICKNESS,
		}),

		Column = React.createElement(ui.Stack, {
			gap = GAP,
			padding = PAD,
			size = UDim2.fromScale(1, 1),
		}, buttons),

		-- The handle rides off the left edge of the column rather than beside a
		-- button, so it's the only thing visible once the bar has slid off the
		-- right.
		Handle = React.createElement("TextButton", {
			Size = UDim2.fromOffset(HANDLE_W, Constants.HANDLE_HEIGHT),
			Position = UDim2.new(0, 1, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundColor3 = Constants.BAR_COLOR,
			BackgroundTransparency = Constants.BAR_TRANSPARENCY,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			-- The arrow points the way the bar will travel: ◀ pulls it in from
			-- the right, ▶ pushes it back out.
			Text = if open then "▶" else "◀",
			TextColor3 = Constants.ARROW_COLOR,
			TextSize = Constants.ARROW_TEXT_SIZE,
			-- No optical correction here, unlike the bottom bar this replaced:
			-- ▲/▼ sit low in their em box and needed nudging up, but ◀/▶ are
			-- centred on the line they're drawn against. If it ever reads as
			-- off-centre, the fix is horizontal padding rather than a text
			-- property — there isn't one that moves a centred glyph.
			[React.Event.Activated] = function()
				setOpen(function(current: boolean): boolean
					return not current
				end)
			end,
		}, {
			UICorner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, math.floor(HANDLE_W / 2)),
			}),
			UIStroke = React.createElement("UIStroke", {
				Color = Constants.OUTLINE_COLOR,
				Thickness = Constants.OUTLINE_THICKNESS,
			}),
		}),
	})
end
