--!strict
-- The reaction bar: a white pill along the bottom of the screen holding one
-- button per slot, with a small arrow tab that slides it in and out. Closed on
-- mount — it's a garnish, and a garnish shouldn't be occupying the bottom of
-- the screen before anyone asks for it.
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
	-- Story hook: start open instead of closed.
	initialOpen: boolean?,
}

local BUTTON = Constants.BUTTON_SIZE
local GAP = Constants.BUTTON_GAP
local PAD = Constants.BAR_PADDING
local HANDLE_H = Constants.HANDLE_HEIGHT

local function barWidth(count: number): number
	return count * BUTTON + math.max(count - 1, 0) * GAP + PAD * 2
end

local BAR_HEIGHT = BUTTON + PAD * 2

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

	local width = barWidth(#props.slots)

	-- Open: the bar's top edge sits a handle's height above the bottom of the
	-- screen. Closed: it drops until only the handle is left poking up. Both
	-- are anchored at the bar's top-center, so the handle above it is the part
	-- that stays on screen either way.
	--
	-- "The bottom of the screen" is the bottom of the *usable* screen: on a phone
	-- the last strip belongs to the home indicator, and a handle hiding under it
	-- is a handle nobody can grab.
	local bottom = ui.useViewport().insets.bottom
	local openPosition = UDim2.new(0.5, 0, 1, -(BAR_HEIGHT + bottom))
	local closedPosition = UDim2.new(0.5, 0, 1, -bottom)
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
		Size = UDim2.fromOffset(width, BAR_HEIGHT),
		-- Rendered at the closed position and then owned by the tween; see
		-- useTweenedUDim2's note on not re-applying the prop.
		Position = if props.initialOpen then openPosition else closedPosition,
		AnchorPoint = Vector2.new(0.5, 0),
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

		Row = React.createElement(ui.Row, {
			gap = GAP,
			padding = PAD,
			size = UDim2.fromScale(1, 1),
		}, buttons),

		-- The handle rides on top of the bar rather than beside it, so it's the
		-- only thing visible once the bar has slid off the bottom.
		Handle = React.createElement("TextButton", {
			Size = UDim2.fromOffset(Constants.HANDLE_WIDTH, HANDLE_H),
			Position = UDim2.new(0.5, 0, 0, 1),
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundColor3 = Constants.BAR_COLOR,
			BackgroundTransparency = Constants.BAR_TRANSPARENCY,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = if open then "▼" else "▲",
			TextColor3 = Constants.ARROW_COLOR,
			TextSize = Constants.ARROW_TEXT_SIZE,
			-- ▲/▼ don't sit on their font's centre line — they're drawn low in
			-- the em box, so a centred TextLabel renders them visibly below the
			-- middle of the handle. Nudged up by hand; there's no text property
			-- that fixes this.
			TextYAlignment = Enum.TextYAlignment.Center,
			[React.Event.Activated] = function()
				setOpen(function(current: boolean): boolean
					return not current
				end)
			end,
		}, {
			UICorner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, math.floor(HANDLE_H / 2)),
			}),
			UIStroke = React.createElement("UIStroke", {
				Color = Constants.OUTLINE_COLOR,
				Thickness = Constants.OUTLINE_THICKNESS,
			}),
			-- The optical correction. Padding the bottom pushes the glyph's own
			-- box up inside the handle, which is the only way to move a centred
			-- character off the layout centre.
			UIPadding = React.createElement("UIPadding", {
				PaddingBottom = UDim.new(0, Constants.ARROW_LIFT),
			}),
		}),
	})
end
