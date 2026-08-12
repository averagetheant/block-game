--!strict
-- Progress toward the next checkpoint, drawn as a journey rather than a bar.
--
--   ●────────────●────────────────○
--   start        tower            next zone
--
-- Two dots mark where this leg began and where it ends; a third rides between
-- them for the tower itself. It measures *this leg only* — from the height the
-- current zone started at to the height that clears it — so the run always
-- begins at the left dot no matter how tall the tower already is.
--
-- The tower is a dot for now; the shape it eventually wants to be is a little
-- stack, which is why the marker is its own element rather than a bar fill.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ui = require(ReplicatedStorage.Shared.Boil).ui

export type Props = {
	-- Studs: where this leg started, where the tower is, where it ends.
	from: number,
	current: number,
	to: number,
	size: UDim2?,
	layoutOrder: number?,
}

local TRACK_HEIGHT = 4
local END_DOT = 14
local TOWER_DOT = 18
-- Inset so the end dots sit fully inside the component rather than half out of it.
local EDGE = END_DOT / 2

local TRACK_COLOR = Color3.fromRGB(52, 56, 72)
local DONE_COLOR = Color3.fromRGB(112, 214, 122)
local TOWER_COLOR = Color3.fromRGB(255, 255, 255)
local GOAL_COLOR = Color3.fromRGB(226, 230, 245)

local function dot(size: number, color: Color3, x: UDim, zIndex: number): any
	return React.createElement("Frame", {
		Size = UDim2.fromOffset(size, size),
		Position = UDim2.new(x.Scale, x.Offset, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Stroke = React.createElement("UIStroke", {
			Thickness = 2,
			Color = Color3.fromRGB(12, 12, 18),
			Transparency = 0.35,
		}),
	})
end

return function(props: Props)
	local span = math.max(props.to - props.from, 1)
	local progress = math.clamp((props.current - props.from) / span, 0, 1)

	return React.createElement("Frame", {
		Size = props.size or UDim2.new(1, 0, 0, TOWER_DOT + 6),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder,
	}, {
		-- Inset both ends by half a dot so nothing hangs off the edge.
		Inner = React.createElement("Frame", {
			Size = UDim2.new(1, -END_DOT, 1, 0),
			Position = UDim2.fromOffset(EDGE, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, {
			Track = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, TRACK_HEIGHT),
				Position = UDim2.fromScale(0, 0.5),
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundColor3 = TRACK_COLOR,
				BorderSizePixel = 0,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
			}),

			-- How far the tower has come, drawn over the track.
			Done = React.createElement("Frame", {
				Size = UDim2.new(progress, 0, 0, TRACK_HEIGHT),
				Position = UDim2.fromScale(0, 0.5),
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundColor3 = DONE_COLOR,
				BorderSizePixel = 0,
				ZIndex = 2,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
			}),

			Start = dot(END_DOT, DONE_COLOR, UDim.new(0, 0), 3),
			Goal = dot(END_DOT, GOAL_COLOR, UDim.new(1, 0), 3),
			Tower = dot(TOWER_DOT, TOWER_COLOR, UDim.new(progress, 0), 4),
		}),
	})
end
