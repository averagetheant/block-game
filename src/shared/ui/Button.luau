--!strict
-- Gem-style button: a Frame outline + invisible Trigger TextButton on top of
-- a GemBackground (with shine) and a Text label (shadow enabled).
--
-- Click handling is wired via the `onClick` prop. The visible visuals are
-- non-interactive — the Trigger at ZIndex 10 captures the press.
--
-- Two frames deep: an outer *box* that holds the caller's size, position and
-- anchor and never moves, and the `Body` centred inside it that draws the button
-- and wears the hover scale. See the note above the render for why the swell
-- can't ride on the box.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Assets = require(script.Parent.assets)
local GemBackground = require(script.Parent.GemBackground)
local Text = require(script.Parent.Text)
local theme = require(script.Parent.theme)
local useHoverScale = require(script.Parent.useHoverScale)

type Props = {
	variant: Assets.VariantKey?,
	text: string?,
	textSize: number?,
	textWeight: Enum.FontWeight?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
	-- Dims the button under a dark overlay and ignores clicks/hover.
	disabled: boolean?,
	onClick: (() -> ())?,
}

-- Semi-transparent black wash drawn over the gem (and its label) while
-- disabled. Sits below the Trigger so the overlay never blocks the tree,
-- only the look.
local DISABLED_OVERLAY_TRANSPARENCY = 0.45

return function(props: Props)
	local variantKey = props.variant or "red"
	local variant = Assets.Variants[variantKey] or Assets.Variants.red
	local text = props.text or ""
	-- Rainbow palette only reads correctly when stops run horizontally.
	local fillRotation = if variantKey == "rainbow" then 0 else 90
	local glowRotation = if variantKey == "rainbow" then 0 else 90

	local disabled = props.disabled == true

	local hover = useHoverScale()

	-- Two frames, and the split is what keeps the hover swell centred.
	--
	-- A UIScale transforms about its own frame's **AnchorPoint**, so when the
	-- scale rode on the outer frame the button grew out of whichever corner it
	-- happened to be anchored by: down and to the right for a layout child (the
	-- default 0,0), up and to the left for anything pinned to a bottom-right
	-- corner. Only a button the caller had already centred swelled about itself.
	--
	-- So the outer frame is the *box*: it takes the caller's size, position,
	-- anchor and layout order, draws nothing, and never changes size. The `Body`
	-- inside it is the button, centred in the box, and carries the scale — which
	-- also stops a hover from shoving its neighbours around, since a UIScale
	-- changes AbsoluteSize as well as what's drawn and the box's own size is what
	-- a UIListLayout measures.
	local body = React.createElement("Frame", {
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
	}, {
		UIScale = React.createElement("UIScale", {
			Scale = 1,
			ref = hover.scaleRef,
		}),

		UIStroke = React.createElement("UIStroke", {
			Thickness = theme.strokeThickness,
			LineJoinMode = Enum.LineJoinMode.Miter,
		}),

		Trigger = React.createElement("TextButton", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Text = "",
			TextColor3 = Color3.fromRGB(0, 0, 0),
			TextSize = 14,
			FontFace = Font.new(
				"rbxasset://fonts/families/SourceSansPro.json",
				Enum.FontWeight.Regular,
				Enum.FontStyle.Normal
			),
			ZIndex = 10,
			[React.Event.MouseEnter] = if disabled then nil else hover.onEnter,
			[React.Event.MouseLeave] = if disabled then nil else hover.onLeave,
			[React.Event.MouseButton1Down] = if disabled then nil else hover.onPress,
			[React.Event.MouseButton1Up] = if disabled then nil else hover.onRelease,
			[React.Event.Activated] = if disabled then nil else props.onClick,
		}),

		DisabledOverlay = if disabled
			then React.createElement("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Color3.fromRGB(0, 0, 0),
				BackgroundTransparency = DISABLED_OVERLAY_TRANSPARENCY,
				BorderSizePixel = 0,
				ZIndex = 9,
			})
			else nil,

		BackgroundDeco = React.createElement(GemBackground, {
			fillGradient = variant.fill,
			glowGradient = variant.glow,
			fillRotation = fillRotation,
			glowRotation = glowRotation,
			hasShine = true,
		}),

		-- ZIndex = 2 keeps the label above BackgroundDeco (at ZIndex 1).
		-- Template uses 1 for both and relies on Studio tree order, which
		-- React-Roblox doesn't guarantee for named children.
		TextLabel = React.createElement(Text, {
			text = text,
			textSize = props.textSize or theme.buttonTextSize,
			weight = props.textWeight or Enum.FontWeight.Bold,
			position = UDim2.fromScale(0.5, 0.5),
			anchorPoint = Vector2.new(0.5, 0.5),
			zIndex = 2,
			shadow = true,
		}),
	})

	return React.createElement("Frame", {
		Size = props.size or theme.buttonSize,
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder,
		ZIndex = props.zIndex or 2,
	}, {
		Body = body,
	})
end
