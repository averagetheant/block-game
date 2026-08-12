--!strict
-- The turn clock: a plain circle with the countdown number in the middle.
-- (sync marker)
--
-- Earlier attempts drew this as a filling pie or a ring (both built from
-- UIGradient hacks to fake a radial fill, since Roblox has no native one) but
-- neither read well in practice. This is the simple version: one circle, whose
-- colour still shifts red under the urgency threshold (handled by the caller via
-- `color`), with the seconds label on top.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ui = require(ReplicatedStorage.Shared.Boil).ui

export type Props = {
	-- Unused for the fill (kept so callers don't need to change), but the
	-- shape's still here for a future radial treatment if one is worth revisiting.
	progress: number,
	color: Color3,
	trackColor: Color3?,
	size: number,
	layoutOrder: number?,
	-- Rendered in the middle of the dial.
	label: string?,
}

return function(props: Props)
	return React.createElement("Frame", {
		Size = UDim2.fromOffset(props.size, props.size),
		BackgroundColor3 = props.color,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Stroke = React.createElement("UIStroke", {
			Thickness = ui.theme.thinStrokeThickness,
			Color = Color3.fromRGB(12, 12, 18),
		}),

		Label = if props.label
			then React.createElement(ui.Text, {
				text = props.label,
				textSize = math.floor(props.size * 0.34),
				weight = Enum.FontWeight.Heavy,
				shadow = true,
				xAlignment = Enum.TextXAlignment.Center,
				yAlignment = Enum.TextYAlignment.Center,
				size = UDim2.fromScale(1, 1),
				zIndex = 3,
			})
			else nil,
	})
end
