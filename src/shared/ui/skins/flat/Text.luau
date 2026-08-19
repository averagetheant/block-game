--!strict
-- Flat Text: a plain label, no drop-shadow/stroke. Honors contract.TextProps;
-- shadow/strokeThickness/foregroundOffset are accepted but ignored.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local contract = require(ReplicatedStorage.Shared.ui.contract)
local theme = require(script.Parent.theme)

-- Matches the gem skin's floor; see the `fit` note in src/shared/ui/Text.luau
-- for why a label is allowed to give text size back at all.
local MIN_FIT_RATIO = 0.8

local function font(weight: Enum.FontWeight?): Font
	return Font.new("rbxasset://fonts/families/SourceSansPro.json", weight or Enum.FontWeight.SemiBold)
end

local function fitConstraint(props: contract.TextProps, textSize: number): any?
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

return function(props: contract.TextProps)
	local textSize = props.textSize or theme.textSize
	local constraint = fitConstraint(props, textSize)

	return React.createElement("TextLabel", {
		Text = props.text,
		TextColor3 = props.color or theme.textColor,
		TextSize = textSize,
		FontFace = font(props.weight),
		BackgroundTransparency = 1,
		Size = props.size or UDim2.fromScale(1, 1),
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		AutomaticSize = props.automaticSize,
		LayoutOrder = props.layoutOrder,
		ZIndex = props.zIndex,
		TextXAlignment = props.xAlignment or Enum.TextXAlignment.Center,
		TextYAlignment = props.yAlignment or Enum.TextYAlignment.Center,
		TextWrapped = props.wrapped,
		TextScaled = constraint ~= nil,
	}, {
		UITextSizeConstraint = constraint,
	})
end
