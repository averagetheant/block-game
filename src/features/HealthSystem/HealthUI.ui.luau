local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local theme = require(ReplicatedStorage.Shared.Boil).ui.theme
local Constants = require(script.Parent.Constants)

return function(props)
	return React.createElement("TextLabel", {
		-- Box tracks the text tier: readable body copy needs the height to
		-- match, or the label clips on a phone where both are halved.
		Size = UDim2.fromOffset(220, theme.textSizeRegular + theme.padding * 2),
		Position = UDim2.fromOffset(16, 16),
		BackgroundColor3 = Color3.fromRGB(20, 20, 26),
		BorderSizePixel = 0,
		TextColor3 = Color3.fromRGB(255, 95, 95),
		Font = Enum.Font.GothamBold,
		TextSize = theme.textSizeRegular,
		Text = `HP: {props.hp or Constants.MAX_HP}`,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 6) }),
	})
end
