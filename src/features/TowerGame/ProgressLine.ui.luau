--!strict
-- Progress toward the next checkpoint, drawn as a climb rather than a bar.
--
--   ○              next zone
--   │
--   │
--   24.5 studs ─●  the tower, carrying its height with it
--   │
--   ●              start
--
-- Vertical because the thing it measures is: the tower goes up, so the marker
-- goes up. Two dots mark where this leg began and where it ends; a third rides
-- between them for the tower itself.
--
-- The height readout is a child of that marker rather than a separate readout
-- somewhere else on the screen — the number and the position are the same fact,
-- so moving one moves the other for free and they can never disagree.
--
-- It measures *this leg only* — from the height the current zone started at to
-- the height that clears it — so a run always begins at the bottom dot no
-- matter how tall the tower already is.
--
-- The tower is a dot for now; the shape it eventually wants to be is a little
-- stack, which is why the marker is its own element rather than a bar fill.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TweenService = game:GetService("TweenService")

local React = require(ReplicatedStorage.Packages.React)
local ui = require(ReplicatedStorage.Shared.Boil).ui

-- Height arrives in steps — a block lands and the number jumps — so the marker
-- and the trail are tweened rather than set. Without this the dot teleports
-- every time a piece settles.
local GLIDE = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

export type Props = {
	-- Studs: where this leg started, where the tower is, where it ends.
	from: number,
	current: number,
	to: number,
	-- Rides beside the marker as it climbs. nil draws the marker alone.
	label: string?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
}

local TRACK_WIDTH = 4
local END_DOT = 14
local TOWER_DOT = 18
-- Inset so the end dots sit fully inside the component rather than half out of it.
local EDGE = END_DOT / 2

-- The readout hangs off the marker's left, because the rail lives on the right
-- edge of the screen and the free space is inward. Wide enough for a four-digit
-- reading ("1234.5 studs") with room to spare — the box is transparent and the
-- space it grows into is open sky, so erring wide costs nothing and erring
-- narrow clips the number.
local LABEL_WIDTH = 260
local LABEL_HEIGHT = 40
local LABEL_GAP = 10
local LABEL_TEXT_SIZE = 34

local TRACK_COLOR = Color3.fromRGB(52, 56, 72)
local DONE_COLOR = Color3.fromRGB(112, 214, 122)
local TOWER_COLOR = Color3.fromRGB(255, 255, 255)
local GOAL_COLOR = Color3.fromRGB(226, 230, 245)

-- The rounding and outline every dot on the rail wears. Built fresh per call
-- rather than shared, so each dot owns its own instances.
local function dotDecor(): { [string]: any }
	return {
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Stroke = React.createElement("UIStroke", {
			Thickness = 2,
			Color = Color3.fromRGB(12, 12, 18),
			Transparency = 0.35,
		}),
	}
end

local function dot(size: number, color: Color3, y: UDim, zIndex: number): any
	return React.createElement("Frame", {
		Size = UDim2.fromOffset(size, size),
		Position = UDim2.new(0.5, 0, y.Scale, y.Offset),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, dotDecor())
end

return function(props: Props)
	local span = math.max(props.to - props.from, 1)
	local progress = math.clamp((props.current - props.from) / span, 0, 1)

	local towerRef = React.useRef(nil :: Frame?)
	local trailRef = React.useRef(nil :: Frame?)

	-- Glide both the marker and the trail to the new progress. Rendered at the
	-- old value and tweened, so a block landing slides the dot up the rail
	-- instead of snapping it.
	React.useEffect(function()
		local tweens = {}
		local tower = towerRef.current
		if tower then
			table.insert(
				tweens,
				TweenService:Create(tower, GLIDE, { Position = UDim2.new(0.5, 0, 1 - progress, 0) })
			)
		end
		local trail = trailRef.current
		if trail then
			table.insert(
				tweens,
				TweenService:Create(trail, GLIDE, { Size = UDim2.new(0, TRACK_WIDTH, progress, 0) })
			)
		end
		for _, tween in tweens do
			tween:Play()
		end

		return function()
			for _, tween in tweens do
				tween:Cancel()
				tween:Destroy()
			end
		end
	end, { progress } :: { any })

	return React.createElement("Frame", {
		Size = props.size or UDim2.new(0, TOWER_DOT + 6, 1, 0),
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder,
	}, {
		-- Inset both ends by half a dot so nothing hangs off the edge.
		Inner = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 1, -END_DOT),
			Position = UDim2.fromOffset(0, EDGE),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, {
			Track = React.createElement("Frame", {
				Size = UDim2.new(0, TRACK_WIDTH, 1, 0),
				Position = UDim2.fromScale(0.5, 0),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundColor3 = TRACK_COLOR,
				BorderSizePixel = 0,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
			}),

			-- How far the tower has come, drawn over the track and growing from
			-- the bottom. Rendered empty and owned by the tween from then on —
			-- re-applying a changed Size prop each render would fight the
			-- animation.
			Done = React.createElement("Frame", {
				ref = trailRef,
				Size = UDim2.new(0, TRACK_WIDTH, 0, 0),
				Position = UDim2.fromScale(0.5, 1),
				AnchorPoint = Vector2.new(0.5, 1),
				BackgroundColor3 = DONE_COLOR,
				BorderSizePixel = 0,
				ZIndex = 2,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
			}),

			Start = dot(END_DOT, DONE_COLOR, UDim.new(1, 0), 3),
			Goal = dot(END_DOT, GOAL_COLOR, UDim.new(0, 0), 3),

			-- The tower, plus whatever rides with it. A container rather than a
			-- bare dot so the readout is carried by the same tween that moves
			-- the marker.
			Tower = React.createElement("Frame", {
				ref = towerRef,
				Size = UDim2.fromOffset(TOWER_DOT, TOWER_DOT),
				-- Rendered at the bottom; the tween owns it from mount on.
				Position = UDim2.new(0.5, 0, 1, 0),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = 4,
			}, {
				Dot = React.createElement("Frame", {
					Size = UDim2.fromScale(1, 1),
					BackgroundColor3 = TOWER_COLOR,
					BorderSizePixel = 0,
				}, dotDecor()),

				Label = if props.label
					then React.createElement(ui.Text, {
						text = props.label,
						textSize = LABEL_TEXT_SIZE,
						weight = Enum.FontWeight.Heavy,
						shadow = true,
						xAlignment = Enum.TextXAlignment.Right,
						size = UDim2.fromOffset(LABEL_WIDTH, LABEL_HEIGHT),
						position = UDim2.new(0, -LABEL_GAP, 0.5, 0),
						anchorPoint = Vector2.new(1, 0.5),
					})
					else nil,
			}),
		}),
	})
end
