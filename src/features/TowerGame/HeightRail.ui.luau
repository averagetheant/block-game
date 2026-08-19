--!strict
-- Every tower in the match on one vertical rail — the PVP answer to the classic
-- climb line (`ProgressLine`), which measures one tower against a checkpoint.
--
--                 ╷        open top: the scale keeps growing
--                 │
--             (◕) │        the leader
--                 │
--  42.5 studs ─(◕)│        you, the only reading in studs
--             (◕)▐│
--             (◕)▐│
--                 ●        the ground every lane started on
--
-- Vertical for the reason the classic rail is: the thing it measures goes up, so
-- the markers go up. Six faces on a shared scale is the whole standings board in
-- a column 52 wide — who is above you, by how much, without a table of numbers
-- down the side of the sky the towers are growing into.
--
-- **Only your own height is a number.** Everyone else is a position on the rail,
-- which is the question a player actually asks mid-match ("am I ahead?") rather
-- than the one a spreadsheet answers ("by 6.5 studs?").
--
-- **The ceiling grows, and only grows.** The rail opens at BASE_MAX studs and
-- steps up whenever the tallest tower comes within HEADROOM of the top, so the
-- pack spends the match in the middle of the rail instead of squashed at the
-- bottom of a scale drawn for the end of it. It never steps back down: a bomb
-- taking the leader's roof off would otherwise rescale the whole board, and
-- every other player would watch their own marker jump for something that
-- happened in someone else's lane.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TweenService = game:GetService("TweenService")

local React = require(ReplicatedStorage.Packages.React)
local ui = require(ReplicatedStorage.Shared.Boil).ui

-- Height arrives in steps — a piece lands and the number jumps — so markers are
-- tweened rather than set. The same glide the classic rail uses, so a face
-- climbing here and a dot climbing there move at one speed.
local GLIDE = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

export type Entry = {
	userId: number,
	-- Studs. Order doesn't matter — the rail sorts for its own layout pass.
	height: number,
	-- Ignored: the rail draws faces, not names. Declared so a caller can hand
	-- over the standings list it already holds rather than rebuild it per frame.
	name: string?,
}

export type Props = {
	entries: { Entry },
	-- Whose marker is lit and carries the studs readout. nil while spectating,
	-- which draws the rail with no reading and no trail on it.
	youUserId: number?,
	-- The box the rail fills. Scale-relative is the point: the band between the
	-- topbar and the corner furniture is a different number of units tall on
	-- every aspect ratio — about 1830 on a portrait phone against 456 on a 16:9
	-- desktop — so a rail authored to one fixed height sits in the top fifth of
	-- the tall screen with the rest of it empty underneath.
	--
	-- The layout pass still needs a real distance to hold faces apart, so the
	-- component measures its own box; see `useMeasuredHeight`.
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
}

-- Studs the rail shows before anybody has climbed into it. Ten blocks
-- (BLOCK_SIZE 4) — a few pieces' worth, so the first tower to land moves a
-- marker visibly instead of nudging it off the floor.
local BASE_MAX = 40
-- How much of the rail the tallest tower may fill before the ceiling steps up.
local HEADROOM = 0.8
-- The ceiling moves in whole steps rather than tracking the leader continuously,
-- so the scale isn't redrawn under everybody every time one piece lands.
local STEP = 40

local FACE = 36
local YOU_FACE = 46
-- How close two face centres may get before they read as one blob. Under a face
-- width on purpose — circles that overlap a little still both resolve, and
-- holding them a full width apart would lie about six towers within a block of
-- each other.
local MIN_GAP = 26

local TRACK_WIDTH = 5
local GROUND_DOT = 14
-- Room for the widest marker plus its ring, so nothing hangs off the component.
-- `PvpHUD` sizes the rail's box and has to agree with this; see RAIL_WIDTH there.
local RAIL_WIDTH = YOU_FACE + 6

-- The readout hangs off your marker's left: the rail lives on the right edge of
-- the screen, so the free space is inward. Same shape as the classic rail's, for
-- the same reason — a four-digit reading with room to spare, in a transparent
-- box growing into open sky.
local LABEL_WIDTH = 240
local LABEL_HEIGHT = 36
local LABEL_GAP = 10
local LABEL_TEXT_SIZE = 32

local TRACK_COLOR = Color3.fromRGB(52, 56, 72)
local DONE_COLOR = Color3.fromRGB(112, 214, 122)
local GROUND_COLOR = Color3.fromRGB(226, 230, 245)
local INK = Color3.fromRGB(12, 12, 18)
-- Your ring, matched to the gold the HUD marks your place with.
local YOU_COLOR = Color3.fromRGB(255, 214, 110)
local FACE_FILL = Color3.fromRGB(38, 42, 58)

-- Roblox resolves this without a web call from us — the same form the turn strip
-- and the results board use, so a face is a face everywhere in the game.
local function headshot(userId: number): string
	return `rbxthumb://type=AvatarHeadShot&id={userId}&w=150&h=150`
end

-- The rail's own height, in the units everything in here is authored in.
--
-- Measured rather than passed, because the rail is sized against the *screen*
-- (see `size`) while its layout pass works in offsets — faces held MIN_GAP
-- apart, a ground dot inset by half of itself. `AbsoluteSize` is device pixels
-- and the whole tree sits under one UIScale, so the scale divides back out.
--
-- A layout effect rather than an ordinary one: it lands before the frame is
-- drawn, so the first paint already has the measurement and no marker is ever
-- shown at a position taken from a box of height 0.
local function useMeasuredHeight(ref: { current: Frame? }): number
	local scale = ui.useViewportScale()
	local height, setHeight = React.useState(0)

	React.useLayoutEffect(function()
		local frame = ref.current
		if not frame then
			return
		end

		local function measure()
			setHeight(frame.AbsoluteSize.Y / scale)
		end

		measure()
		local connection = frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(measure)

		return function()
			connection:Disconnect()
		end
	end, { scale } :: { any })

	return height
end

-- The ceiling the rail draws to, given the tallest tower on it. Pure, and
-- monotonic in `tallest` — the caller is what makes it one-way over *time* (see
-- the ratchet in the component body).
local function ceilingFor(tallest: number): number
	local needed = tallest / HEADROOM
	if needed <= BASE_MAX then
		return BASE_MAX
	end
	return BASE_MAX + STEP * math.ceil((needed - BASE_MAX) / STEP)
end

-- Where each marker sits, top-down in pixels, with faces held MIN_GAP apart.
--
-- Two passes, which is what makes a bunched pack behave at both ends of the
-- rail. The first walks down from the leader pushing collisions *away from the
-- top*; on its own that dumps six towers all sitting at 0 studs off the bottom
-- of the component — which is every match's first ten seconds. The second only
-- runs when that happened, and pushes the overflowing stack back up off the
-- ground dot.
local function stack(entries: { Entry }, ceiling: number, railHeight: number): { number }
	local positions = table.create(#entries)
	for index, entry in entries do
		local progress = math.clamp(entry.height / ceiling, 0, 1)
		local y = (1 - progress) * railHeight
		local above = positions[index - 1]
		if above and y < above + MIN_GAP then
			y = above + MIN_GAP
		end
		positions[index] = y
	end

	local last = positions[#positions]
	if last == nil or last <= railHeight then
		return positions
	end

	positions[#positions] = railHeight
	for index = #positions - 1, 1, -1 do
		local below = positions[index + 1]
		if positions[index] > below - MIN_GAP then
			positions[index] = below - MIN_GAP
		end
	end
	return positions
end

-- One lane's face, riding the rail. Its own component so it owns its own tween:
-- a marker mounts when a player joins the match and unmounts when their lane is
-- retired, and neither should disturb the five beside it.
local function Marker(props: {
	userId: number,
	y: number,
	you: boolean,
	label: string?,
})
	local ref = React.useRef(nil :: Frame?)
	-- Mount position, frozen. Every later render hands React this same value, so
	-- the tween below owns Position from the first update on rather than fighting
	-- a prop that keeps snapping it back.
	local mountY = React.useRef(props.y)

	React.useEffect(function()
		local frame = ref.current
		if not frame then
			return
		end
		local tween = TweenService:Create(frame, GLIDE, { Position = UDim2.new(0.5, 0, 0, props.y) })
		tween:Play()

		return function()
			tween:Cancel()
			tween:Destroy()
		end
	end, { props.y })

	local size = if props.you then YOU_FACE else FACE

	return React.createElement("Frame", {
		ref = ref,
		Size = UDim2.fromOffset(size, size),
		Position = UDim2.new(0.5, 0, 0, mountY.current),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		-- Yours over everyone else's: when the pack is bunched, the face you are
		-- looking for is the one that must not end up underneath.
		ZIndex = if props.you then 8 else 6,
	}, {
		-- Raw ImageLabel for the reason the results board gives: the kit has no
		-- avatar primitive, and an avatar chip is game content rather than
		-- something worth adding to the skin contract.
		Face = React.createElement("ImageLabel", {
			Image = headshot(props.userId),
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = FACE_FILL,
			-- Rivals recede a little; you don't. The rail is read by finding
			-- yourself first and everyone else relative to you.
			BackgroundTransparency = if props.you then 0 else 0.25,
			ImageTransparency = if props.you then 0 else 0.15,
			BorderSizePixel = 0,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
			Stroke = React.createElement("UIStroke", {
				Thickness = if props.you then 3 else 2,
				Color = if props.you then YOU_COLOR else INK,
				Transparency = if props.you then 0 else 0.35,
			}),
		}),

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
	})
end

return function(props: Props)
	local frameRef = React.useRef(nil :: Frame?)
	local measured = useMeasuredHeight(frameRef)

	-- Tallest first, on a copy: the layout pass walks the pack in order, and
	-- depending on the caller to have sorted it would make a display bug out of
	-- an ordering the caller never promised.
	local ordered = table.clone(props.entries)
	table.sort(ordered, function(a, b)
		-- Ties broken on user id rather than left to the sort, which is unstable:
		-- six lanes all at 0 studs is every match's first ten seconds, and faces
		-- that swapped places on a re-render would each tween to the other's spot
		-- for nothing.
		if a.height == b.height then
			return a.userId < b.userId
		end
		return a.height > b.height
	end)

	local tallest = if ordered[1] then ordered[1].height else 0

	-- The ratchet. It resets when the component unmounts, which is once per match
	-- (`PvpView` renders nothing at all between them), so a new match opens on a
	-- fresh scale without anyone having to clear it.
	local ceiling, setCeiling = React.useState(BASE_MAX)
	React.useEffect(function()
		local wanted = ceilingFor(tallest)
		setCeiling(function(previous)
			-- Returning the same value makes React bail out of the update, so a
			-- match spent under one ceiling costs a comparison per height change
			-- rather than a render.
			return if wanted > previous then wanted else previous
		end)
	end, { tallest })

	-- The band the markers actually ride, inset by half the ground dot at each
	-- end so nothing hangs off the component. 0 for the render that mounts the
	-- box the measurement is taken from — the track and the ground dot draw
	-- against the parent's own size and are fine, and the markers wait a beat
	-- rather than mount at a position taken from a box of height 0 and then
	-- glide down from the top of the rail on every match.
	local inner = math.max(measured - GROUND_DOT, 0)
	local positions = stack(ordered, ceiling, inner)

	local youIndex: number? = nil
	local children: { [string]: any } = {}
	for index, entry in ordered do
		local you = entry.userId == props.youUserId
		if you then
			youIndex = index
		end
		if inner <= 0 then
			continue
		end
		children[`Lane{entry.userId}`] = React.createElement(Marker, {
			userId = entry.userId,
			y = positions[index],
			you = you,
			label = if you then `{string.format("%.1f", entry.height)} studs` else nil,
		})
	end

	-- How far you have come, drawn over the track. It ends at your marker rather
	-- than at your true height, so the trail and the face it belongs to can't
	-- disagree when the layout pass has nudged you clear of a neighbour.
	local trailRef = React.useRef(nil :: Frame?)
	local trail = if youIndex then inner - positions[youIndex] else 0

	React.useEffect(function()
		local frame = trailRef.current
		if not frame then
			return
		end
		local tween = TweenService:Create(frame, GLIDE, { Size = UDim2.new(0, TRACK_WIDTH, 0, trail) })
		tween:Play()

		return function()
			tween:Cancel()
			tween:Destroy()
		end
	end, { trail })

	children.Track = React.createElement("Frame", {
		Size = UDim2.new(0, TRACK_WIDTH, 1, 0),
		Position = UDim2.fromScale(0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = TRACK_COLOR,
		BorderSizePixel = 0,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
		-- The top fades out instead of ending in a cap. The classic rail's top is
		-- a checkpoint — somewhere you can arrive — and it gets a dot; this one is
		-- whatever the ceiling happens to be this minute, and a hard end would
		-- read as a finish line nobody is racing to.
		Fade = React.createElement("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.18, 0),
				NumberSequenceKeypoint.new(1, 0),
			}),
		}),
	})

	children.Done = React.createElement("Frame", {
		ref = trailRef,
		-- Rendered empty and owned by the tween from then on.
		Size = UDim2.new(0, TRACK_WIDTH, 0, 0),
		Position = UDim2.fromScale(0.5, 1),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = DONE_COLOR,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
	})

	children.Ground = React.createElement("Frame", {
		Size = UDim2.fromOffset(GROUND_DOT, GROUND_DOT),
		Position = UDim2.fromScale(0.5, 1),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = GROUND_COLOR,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Stroke = React.createElement("UIStroke", {
			Thickness = 2,
			Color = INK,
			Transparency = 0.35,
		}),
	})

	return React.createElement("Frame", {
		ref = frameRef,
		Size = props.size or UDim2.new(0, RAIL_WIDTH, 1, 0),
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder,
	}, {
		-- The track and the markers live in an inset box, so the ground dot sits
		-- fully inside the component rather than half out of the bottom of it.
		Inner = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 1, -GROUND_DOT),
			Position = UDim2.fromOffset(0, GROUND_DOT / 2),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, children),
	})
end
