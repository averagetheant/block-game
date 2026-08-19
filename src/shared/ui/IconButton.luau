--!strict
-- Gem-style icon button: same outer stack as Button (Frame outline + invisible
-- Trigger TextButton + GemBackground with shine + hover scale) but with an
-- ImageLabel where the text label would be. Use this for HUD action bars and
-- anywhere you want a square gem with no copy.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Assets = require(script.Parent.assets)
local GemBackground = require(script.Parent.GemBackground)
local theme = require(script.Parent.theme)
local useHoverScale = require(script.Parent.useHoverScale)

type Props = {
	variant: Assets.VariantKey?,
	icon: string?, -- rbxassetid:// for the icon; falls back to a placeholder.
	iconColor: Color3?,
	-- ImageLabel size relative to the button (0..1). Default leaves an 8px
	-- visual margin between the icon and the gem outline.
	iconScale: number?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
	onClick: (() -> ())?,
}

local PLACEHOLDER_IMAGE = "rbxasset://textures/ui/GuiImagePlaceholder.png"
local WHITE = Color3.fromRGB(255, 255, 255)

return function(props: Props)
	local variantKey = props.variant or "red"
	local variant = Assets.Variants[variantKey] or Assets.Variants.red
	local fillRotation = if variantKey == "rainbow" then 0 else 90
	local glowRotation = if variantKey == "rainbow" then 0 else 90
	local iconScale = props.iconScale or 0.6

	local hover = useHoverScale()

	-- Box outside, body inside — the same split Button makes, for the same
	-- reason: a UIScale transforms about its frame's AnchorPoint, so a swell on
	-- the outer frame grows out of whatever corner the caller anchored the button
	-- by. These sit in screen corners more often than Buttons do (the camera
	-- toggle is pinned bottom-right, the rail's actions to a list), which is
	-- exactly where an off-centre swell is most obvious.
	local body = React.createElement("Frame", {
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = WHITE,
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
			BackgroundColor3 = WHITE,
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
			[React.Event.MouseEnter] = hover.onEnter,
			[React.Event.MouseLeave] = hover.onLeave,
			[React.Event.MouseButton1Down] = hover.onPress,
			[React.Event.MouseButton1Up] = hover.onRelease,
			[React.Event.Activated] = props.onClick,
		}),

		BackgroundDeco = React.createElement(GemBackground, {
			fillGradient = variant.fill,
			glowGradient = variant.glow,
			fillRotation = fillRotation,
			glowRotation = glowRotation,
			hasShine = true,
		}),

		IconImage = React.createElement("ImageLabel", {
			Size = UDim2.fromScale(iconScale, iconScale),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = props.icon or PLACEHOLDER_IMAGE,
			ImageColor3 = props.iconColor or WHITE,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 2,
		}, {
			UIAspectRatioConstraint = React.createElement("UIAspectRatioConstraint", {}),
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
