--!strict
-- General text primitive using the gem display font.
--
-- Always renders a Miter UIStroke (thickness defaults to `theme.thinStrokeThickness`).
-- The stroke is independent of the shadow effect — pass `strokeThickness = 0`
-- to omit it.
--
-- `shadow = true` opts into the two-layer drop-shadow effect used by the gem
-- primitives (outer TextLabel paints `shadowColor`, inner `FgTextLabel` paints
-- `color` offset upward by `foregroundOffset` pixels, both with the same stroke).
--
-- `fit` is the device safety net (on by default for `wrapped` copy). Glyph
-- metrics don't scale perfectly linearly: at the ~0.5 UIScale a phone gets, each
-- advance rounds to a whole device pixel, so a sentence that wraps to exactly
-- two lines on a monitor can need a third one on a handset — and the third line
-- is simply not drawn. `fit` lets the label give back a few pixels of text size
-- (never above the authored `textSize`, never below `minTextSize`) instead of
-- losing a line. It changes nothing where the copy already fits, which is every
-- desktop viewport and the UI Labs preview.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Assets = require(script.Parent.assets)
local theme = require(script.Parent.theme)

type Props = {
	text: string,
	textSize: number?,
	weight: Enum.FontWeight?,
	color: Color3?,
	xAlignment: Enum.TextXAlignment?,
	yAlignment: Enum.TextYAlignment?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
	automaticSize: Enum.AutomaticSize?,
	-- Wrap at the label's width. Pair with `automaticSize = Y` for copy that
	-- sizes to its content.
	wrapped: boolean?,
	-- Shrink the rendered text (never past `minTextSize`) rather than let it
	-- overflow the box. Defaults to `wrapped`; pass `false` to opt a wrapped
	-- label out, or `true` for a single-line label that must stay inside its
	-- box. Ignored when `automaticSize` is set — a box that grows to its text
	-- and text that shrinks to its box would be solving the same problem twice.
	fit: boolean?,
	-- Floor for `fit`. Defaults to MIN_FIT_RATIO of `textSize`.
	minTextSize: number?,
	-- Shadow (drop-shadow) feature.
	shadow: boolean?,
	shadowColor: Color3?,
	strokeThickness: number?,
	foregroundOffset: number?,
}

local WHITE = Color3.fromRGB(255, 255, 255)
local BLACK = Color3.fromRGB(0, 0, 0)

-- How far `fit` may go before it stops rescuing the label. It exists to absorb
-- rounding, not to make a box hold copy it was never sized for: past this the
-- text is small enough that the box is the bug, and clipping is the honest
-- signal. Keep it high enough that a shrunk label stays on the ladder's tier.
local MIN_FIT_RATIO = 0.8

-- The UITextSizeConstraint that bounds `fit`, or nil when the label isn't
-- fitting. `TextScaled` alone would *grow* text to fill its box; the MaxTextSize
-- here is what keeps the authored tier as the ceiling, so a label only ever
-- gives size back.
local function fitConstraint(props: Props, textSize: number): any?
	local enabled = if props.fit ~= nil then props.fit else props.wrapped == true
	if not enabled or props.automaticSize ~= nil then
		return nil
	end
	local floor = props.minTextSize or math.floor(textSize * MIN_FIT_RATIO)
	return React.createElement("UITextSizeConstraint", {
		MaxTextSize = textSize,
		MinTextSize = math.clamp(floor, 1, textSize),
	})
end

return function(props: Props)
	local textSize = props.textSize or theme.textSize
	local font = Font.new(
		Assets.DISPLAY_FONT_ID,
		props.weight or Enum.FontWeight.Bold,
		Enum.FontStyle.Normal
	)
	local xAlign = props.xAlignment or Enum.TextXAlignment.Center
	local yAlign = props.yAlignment or Enum.TextYAlignment.Center
	local color = props.color or WHITE
	local strokeThickness = props.strokeThickness or theme.thinStrokeThickness

	if not props.shadow then
		local children: { [string]: any } = {}
		if strokeThickness > 0 then
			children.UIStroke = React.createElement("UIStroke", {
				Thickness = strokeThickness,
				LineJoinMode = Enum.LineJoinMode.Miter,
			})
		end
		local constraint = fitConstraint(props, textSize)
		children.UITextSizeConstraint = constraint
		return React.createElement("TextLabel", {
			Size = props.size or UDim2.fromScale(1, 1),
			Position = props.position,
			AnchorPoint = props.anchorPoint,
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Text = props.text,
			TextColor3 = color,
			TextSize = textSize,
			FontFace = font,
			TextXAlignment = xAlign,
			TextYAlignment = yAlign,
			LayoutOrder = props.layoutOrder,
			ZIndex = props.zIndex,
			AutomaticSize = props.automaticSize,
			TextWrapped = props.wrapped,
			TextScaled = constraint ~= nil,
		}, children)
	end

	local shadowColor = props.shadowColor or BLACK
	-- Both layers get their own constraint. They're the same text in the same
	-- box (the foreground fills its parent), so they land on the same size and
	-- the shadow stays registered under the label rather than drifting.
	local shadowFit = fitConstraint(props, textSize)
	local foregroundFit = fitConstraint(props, textSize)

	return React.createElement("TextLabel", {
		Size = props.size or UDim2.fromScale(1, 1),
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = props.text,
		TextColor3 = shadowColor,
		TextSize = textSize,
		FontFace = font,
		TextXAlignment = xAlign,
		TextYAlignment = yAlign,
		LayoutOrder = props.layoutOrder,
		ZIndex = props.zIndex,
		AutomaticSize = props.automaticSize,
		TextWrapped = props.wrapped,
		TextScaled = shadowFit ~= nil,
	}, {
		UIStroke = React.createElement("UIStroke", {
			Thickness = strokeThickness,
			LineJoinMode = Enum.LineJoinMode.Miter,
		}),
		UITextSizeConstraint = shadowFit,

		FgTextLabel = React.createElement("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.fromOffset(0, props.foregroundOffset or theme.textForegroundOffset),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Text = props.text,
			TextColor3 = color,
			TextSize = textSize,
			FontFace = font,
			TextXAlignment = xAlign,
			TextYAlignment = yAlign,
			TextWrapped = props.wrapped,
			TextScaled = foregroundFit ~= nil,
		}, {
			UIStroke = React.createElement("UIStroke", {
				Thickness = strokeThickness,
				LineJoinMode = Enum.LineJoinMode.Miter,
			}),
			UITextSizeConstraint = foregroundFit,
		}),
	})
end
