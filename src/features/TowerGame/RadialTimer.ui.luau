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

-- The pop-in. Back/Out overshoots slightly before settling, which is what makes
-- it read as arriving rather than as fading up — the dial exists for exactly one
-- turn and its appearance is the cue that the turn started.
local APPEAR_TWEEN = TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- The countdown's text size, as a fraction of the dial. Derived rather than
-- fixed so the number keeps its weight at whatever size the caller asks for.
-- Kept below ~0.5: the label is centred in a circle, so a glyph much larger
-- than this starts colliding with the curve at the top and bottom rather than
-- filling it.
local LABEL_FIT = 0.42

export type Props = {
	-- Unused for the fill (kept so callers don't need to change), but the
	-- shape's still here for a future radial treatment if one is worth revisiting.
	progress: number,
	color: Color3,
	trackColor: Color3?,
	size: number,
	layoutOrder: number?,
	-- Placed absolutely by the caller rather than laid out in a row: the dial
	-- must not take space from anything, or its arrival each turn would push the
	-- rest of the HUD around. See TowerHUD.
	position: UDim2?,
	anchorPoint: Vector2?,
	-- Rendered in the middle of the dial.
	label: string?,
}

return function(props: Props)
	-- Scale 0 on the first frame, then tweened to 1 once mounted. The hook
	-- tracks the UIScale in state and re-runs when it actually appears, so this
	-- can't fire against a nil instance and silently skip the animation.
	local shown, setShown = React.useState(false)
	React.useEffect(function()
		setShown(true)
	end, {})
	local scaleRef = ui.useTweenedScale(if shown then 1 else 0, { tweenInfo = APPEAR_TWEEN })

	return React.createElement("Frame", {
		Size = UDim2.fromOffset(props.size, props.size),
		Position = props.position,
		-- Centre by default so the pop scales about the dial's middle. A UIScale
		-- transforms about its parent's AnchorPoint, so a corner anchor would
		-- make it grow out of that corner instead.
		AnchorPoint = props.anchorPoint or Vector2.new(0.5, 0.5),
		BackgroundColor3 = props.color,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder,
	}, {
		Scale = React.createElement("UIScale", { Scale = 0, ref = scaleRef }),
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Stroke = React.createElement("UIStroke", {
			Thickness = ui.theme.thinStrokeThickness,
			Color = Color3.fromRGB(12, 12, 18),
		}),

		Label = if props.label
			then React.createElement(ui.Text, {
				text = props.label,
				textSize = math.floor(props.size * LABEL_FIT),
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
