--!strict
-- The turn clock as a filling pie.
--
-- Roblox has no radial fill, so this is the standard two-halves construction:
-- the circle is split down the middle into two clipping frames, and each holds a
-- half-disc that pivots about the circle's centre. The right half sweeps the
-- first 180°, the left half the rest, which together read as one wedge growing
-- clockwise from twelve o'clock.
--
-- Each half is four nested frames — clip, pivot, clip, disc — because a rotated
-- circle looks identical to an unrotated one. The rotation has to be applied to
-- a *half* disc, and the only way to cut a half disc without an image asset is
-- to clip a whole one.
--
-- No assets, no per-frame work: the only thing that changes as time runs out is
-- two Rotation numbers.

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

-- One half of the pie. `side` decides which way it sweeps; `degrees` is how much
-- of this half's 180° is showing.
local function halfDisc(side: "left" | "right", degrees: number, color: Color3): any
	local isRight = side == "right"
	-- 0° parks the disc entirely outside its own clip; 180° fills it exactly.
	local rotation = degrees - 180

	return React.createElement("Frame", {
		Size = UDim2.fromScale(0.5, 1),
		Position = UDim2.fromScale(if isRight then 0.5 else 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, {
		-- Anchored on the circle's centre, which sits on this clip's inner edge,
		-- so rotating it sweeps around the middle of the dial rather than the
		-- middle of the half.
		Pivot = React.createElement("Frame", {
			Size = UDim2.fromScale(2, 1),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(if isRight then 0 else 1, 0.5),
			Rotation = rotation,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, {
			-- The half of the disc that leads the sweep.
			Cut = React.createElement("Frame", {
				Size = UDim2.fromScale(0.5, 1),
				Position = UDim2.fromScale(if isRight then 0.5 else 0, 0),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ClipsDescendants = true,
			}, {
				Disc = React.createElement("Frame", {
					Size = UDim2.fromScale(2, 1),
					Position = UDim2.fromScale(if isRight then -1 else 0, 0),
					BackgroundColor3 = color,
					BorderSizePixel = 0,
				}, {
					Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
				}),
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
