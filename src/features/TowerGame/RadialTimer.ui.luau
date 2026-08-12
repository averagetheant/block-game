--!strict
-- The turn clock as a filling pie.
--
-- Roblox has no radial fill, so this is built from two half-discs — the right
-- one sweeps the first 180°, the left one the rest — which together read as a
-- wedge growing clockwise from twelve o'clock.
--
-- The interesting part is how a half-disc is cut. The obvious approach (clip a
-- circle with a rotated frame) does not work: **ClipsDescendants is ignored on
-- anything inside a rotated ancestor**, so the clip silently does nothing and
-- you get a full circle. Instead the rotation lives in a UIGradient whose alpha
-- steps hard from opaque to invisible at its midpoint. That cuts the disc along
-- a diameter at any angle while every frame stays unrotated — so the outer
-- half-width clip *does* work, and the intersection of the two gives the wedge.
--
-- Nothing animates per frame; two gradient rotations change as the clock drains.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ui = require(ReplicatedStorage.Shared.Boil).ui

export type Props = {
	-- 0 = empty, 1 = full circle.
	progress: number,
	color: Color3,
	trackColor: Color3?,
	size: number,
	layoutOrder: number?,
	-- Rendered in the middle of the dial.
	label: string?,
}

-- A hard alpha step at the halfway point: everything before it is drawn, and
-- everything after is gone. Rotating this cuts the circle along a diameter.
local HALF_CUT = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(0.501, 1),
	NumberSequenceKeypoint.new(1, 1),
})

-- One half of the dial. `degrees` is how much of this half's 180° shows.
local function halfDisc(side: "left" | "right", degrees: number, color: Color3): any
	local isRight = side == "right"
	-- The gradient's cut line starts along the vertical (twelve o'clock) and
	-- turns with the sweep. The right half sweeps down from the top; the left
	-- half continues from the bottom.
	local rotation = (if isRight then -90 else 90) + degrees

	return React.createElement("Frame", {
		-- Unrotated, so this clip actually clips.
		Size = UDim2.fromScale(0.5, 1),
		Position = UDim2.fromScale(if isRight then 0.5 else 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, {
		Disc = React.createElement("Frame", {
			-- Full circle, positioned so its centre sits on the clip's inner edge
			-- (the middle of the dial).
			Size = UDim2.fromScale(2, 1),
			Position = UDim2.fromScale(if isRight then 0 else -1, 0),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
			Cut = React.createElement("UIGradient", {
				Rotation = rotation,
				Transparency = HALF_CUT,
			}),
		}),
	})
end

return function(props: Props)
	local progress = math.clamp(props.progress, 0, 1)
	local sweep = progress * 360

	return React.createElement("Frame", {
		Size = UDim2.fromOffset(props.size, props.size),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder,
	}, {
		-- The unfilled remainder, so an empty dial still reads as a dial.
		Track = React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = props.trackColor or Color3.fromRGB(28, 30, 40),
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
		}),

		Right = halfDisc("right", math.min(sweep, 180), props.color),
		Left = halfDisc("left", math.max(sweep - 180, 0), props.color),

		Ring = React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 2,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
			Stroke = React.createElement("UIStroke", {
				Thickness = ui.theme.thinStrokeThickness,
				Color = Color3.fromRGB(12, 12, 18),
			}),
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
