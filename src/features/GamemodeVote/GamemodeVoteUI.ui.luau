--!strict
-- The vote screen: one panel per gamemode, the clock outside underneath them.
--
-- Dumb by construction (see docs/game/headless-core.md) — it takes the ballot,
-- who voted for what, and a clock, and calls `onVote` with an id. It doesn't
-- know a packet exists, doesn't decide the winner, and doesn't run the clock.
--
-- A vote reads as presence rather than a number: your headshot lands in a row
-- along the bottom of the panel you picked, clear of the icon and the name.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local React = require(ReplicatedStorage.Packages.React)
local ui = require(ReplicatedStorage.Shared.Boil).ui
local Registry = require(script.Parent.Registry)

local theme = ui.theme

-- Sized so a full ballot fits a narrow screen rather than so one panel looks its
-- best: the row auto-sizes on X and is centered, so N panels take
-- N * PANEL_WIDTH + (N-1) * contentSpacing and anything past the viewport is
-- simply off it. TowerGame's ballot is four — Classic and PVP permanently, plus
-- two rolled twists — which at this width lands just over 1000px, inside the
-- 1280 reference on a phone in landscape. Five panels (1260) is the point where
-- this needs revisiting.
--
-- 190 was too narrow for what the panel actually holds: at the body tier it
-- fits about ten characters a line, so every blurb in TowerGame's ballot needed
-- three or four lines to say itself and got two.
local PANEL_WIDTH = 240
-- Height follows the body stack, not the other way round: icon + name + blurb +
-- the Stack's gaps and inset, plus the voter strip. The blurb is real copy a
-- player reads to pick a mode, so it sits on the body tier and gets the rows it
-- needs at this width rather than shrinking to fit on one line.
local PANEL_HEIGHT = 370
local ICON_SIZE = 78
-- Every row box below is `tier * rows + ROW_SLACK`, never the bare product. A
-- box sized to exactly its rows has nowhere to put the pixel a line picks up
-- when the viewport scale rounds it — and the row that no longer fits isn't
-- squeezed, it's dropped, which is what ate the last line of these on a phone.
-- `fit` on each label covers whatever the slack doesn't.
local ROW_SLACK = 8
-- Two rows: a mode name is a registered feature's copy, and "Lightning Storm"
-- doesn't fit one line of a panel this wide.
local NAME_HEIGHT = theme.textSizeRegular * 2 + ROW_SLACK
local BLURB_HEIGHT = theme.textSizeRegular * 3 + ROW_SLACK
local AVATAR_SIZE = 34
-- The stamp. It starts oversized and slams down to 1 — a vote is a commitment
-- and the screen should feel it, so this lands rather than fading in.
local STAMP_SCALE_FROM = 2.2
local STAMP_SECONDS = 0.18
-- Max tilt either way, in degrees. Small: a stamp is *slightly* crooked, and
-- much past this reads as a bug rather than as hand-placed.
local STAMP_ROTATION = 14
-- How far stamps scatter from the centre of the strip — X as a fraction of the
-- panel's width, Y in pixels. Overlap is fine and wanted; stamps piling onto
-- each other is what makes a popular panel *look* popular.
local STAMP_SPREAD_X = 0.44
local STAMP_SPREAD_Y = 14

-- The tag on a stamp worth more than one vote (the 2x Votes gamepass). Yellow
-- and small: it's a note on the stamp, not a second stamp.
local WEIGHT_COLOR = Color3.fromRGB(255, 214, 92)
local WEIGHT_WIDTH = 40
local WEIGHT_HEIGHT = 26

-- What a panel that lost fades to once the winner is in. Panel's default glass
-- is 0.8; pushing it further sinks the losers behind the winner.
local LOST_TRANSPARENCY = 0.92

-- Hover. Deliberately smaller than the kit's `theme.hoverScale` (1.06), which is
-- tuned for a button: 6% of a 240x370 panel is a shove rather than a lift. 3% is
-- about seven pixels across — enough to see which one you're pointing at, small
-- enough that running the pointer along the row doesn't set the ballot rocking.
local HOVER_SCALE = 1.03
-- The press. A vote already lands hard (the stamp), so this is only the moment
-- before it.
local PRESS_SCALE = 0.98
-- Glass under the pointer, against Panel's 0.8 default and LOST_TRANSPARENCY's
-- 0.92. All three states then read on one axis: out, in, and the one you're
-- about to pick.
local HOVER_TRANSPARENCY = 0.72
-- Where a lifted panel sits relative to its neighbours (all at 1).
local HOVER_ZINDEX = 2

export type Props = {
	-- The ballot, in display order.
	options: { Registry.Gamemode },
	-- gamemode id -> the user ids that voted for it.
	votersByOption: { [string]: { number } },
	-- userId -> what that vote counts for. Absent (or 1) is an ordinary vote;
	-- anything more tags the stamp. One stamp either way — the row shows who is
	-- on a panel, and a second headshot would read as a second player.
	voteWeights: { [number]: number }?,
	-- userId -> how many times that player has pressed a panel this poll. The
	-- number itself means nothing to the screen; a *change* to it replays that
	-- voter's slam. It's what makes pressing your own panel again do something,
	-- now that doing so re-stamps the vote instead of taking it back — nothing
	-- else about the stamp changes, so the animation is the whole feedback.
	voteStamps: { [number]: number }?,
	secondsLeft: number,
	-- Set once the poll is resolved; until then the clock is what's shown.
	winnerId: string?,
	onVote: (optionId: string) -> (),
	-- Injected by <UIShell.Frame> for the open/close scale tween.
	scaleRef: any?,
	initialScale: number?,
}

local function headshot(userId: number): string
	return `rbxthumb://type=AvatarHeadShot&id={userId}&w=150&h=150`
end

-- Where a voter's stamp lands and how far it's turned.
--
-- Hashed from the user id rather than rolled, for the same reason cursor colours
-- are: it costs nothing, every client places the stamps identically, and — the
-- part that actually matters here — it's *stable across re-renders*. A
-- `math.random` in the render body would re-roll the whole wall of stamps every
-- time anyone else voted.
--
-- The multipliers are three arbitrary irrationals; using one for all three would
-- correlate the offsets and tilt, and the stamps would fall along a diagonal.
local function stampFor(userId: number): (number, number, number)
	local x = (userId * 0.6180339887) % 1
	local y = (userId * 0.7548776662) % 1
	local turn = (userId * 0.4142135624) % 1
	return (x - 0.5) * STAMP_SPREAD_X, (y - 0.5) * STAMP_SPREAD_Y, (turn - 0.5) * 2 * STAMP_ROTATION
end

-- One voter: a circle with a thin stroke, stamped onto the panel it voted for.
--
-- The stamp is the whole point of the animation — it lands hard rather than
-- fading in, because a vote is a commitment and the screen should feel it. The
-- scale is driven by TweenService off a ref rather than by state, so the slam
-- costs no re-renders and can't fight React over the value.
--
-- `stamp` is the press count for this voter, and the slam is keyed to it rather
-- than to mounting: pressing the panel you already hold re-stamps the vote
-- (nothing is taken back), and that press moves nothing, so the animation is the
-- entire feedback. Re-armed by setting the scale back before each tween — the
-- previous one left it at 1, and a tween to the value it already holds is no
-- animation at all.
local function Avatar(props: { userId: number, weight: number?, stamp: number? })
	local scaleRef = React.useRef(nil :: UIScale?)
	local offsetX, offsetY, rotation = stampFor(props.userId)
	local weight = props.weight or 1

	React.useEffect(function()
		local scale = scaleRef.current
		if scale == nil then
			return
		end
		scale.Scale = STAMP_SCALE_FROM
		local tween = TweenService:Create(
			scale,
			TweenInfo.new(STAMP_SECONDS, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Scale = 1 }
		)
		tween:Play()
		return function()
			tween:Cancel()
			tween:Destroy()
		end
		-- Defaulted rather than passed through: a nil in a Lua dependency array is
		-- a *hole*, so it changes the array's length instead of its contents, and
		-- that's not a comparison to ask React to make. nil means "no count for
		-- this voter" (the story's stand-ins), which is a stable 0 here.
	end, { props.stamp or 0 })

	return React.createElement("ImageLabel", {
		Size = UDim2.fromOffset(AVATAR_SIZE, AVATAR_SIZE),
		-- Scattered around the centre of the strip rather than laid out in a row.
		Position = UDim2.new(0.5 + offsetX, 0, 0.5, offsetY),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = rotation,
		BackgroundColor3 = Color3.fromRGB(24, 26, 34),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Image = headshot(props.userId),
	}, {
		-- Rendered mid-slam; the tween above owns it from here.
		Scale = React.createElement("UIScale", {
			Scale = STAMP_SCALE_FROM,
			ref = scaleRef,
		}),
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Stroke = React.createElement("UIStroke", {
			Thickness = 1,
			Color = Color3.fromRGB(255, 255, 255),
			Transparency = 0.2,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		-- A heavier vote says so on the stamp. It rides the same rotation as the
		-- headshot (it's a child), so it stays part of the stamp rather than
		-- looking like a label pinned over one.
		Weight = if weight > 1
			then React.createElement(ui.Text, {
				text = `{weight}x`,
				textSize = theme.textSizeRegular,
				weight = Enum.FontWeight.Heavy,
				color = WEIGHT_COLOR,
				shadow = true,
				size = UDim2.fromOffset(WEIGHT_WIDTH, WEIGHT_HEIGHT),
				-- Straddling the bottom edge rather than the corner: the stamp is
				-- a circle, and a corner tag on a circle floats off it.
				position = UDim2.new(0.5, 0, 1, 0),
				anchorPoint = Vector2.new(0.5, 0.5),
				zIndex = 3,
			})
			else nil,
	})
end

-- One mode on the ballot: the panel, and the button the panel is.
--
-- A component rather than a function returning elements, which is what it used
-- to be — hover is state, and state needs a component to live in.
local function OptionPanel(props: {
	option: Registry.Gamemode,
	voters: { number },
	voteWeights: { [number]: number },
	voteStamps: { [number]: number },
	faded: boolean,
	locked: boolean,
	layoutOrder: number,
	onVote: () -> (),
}): any
	-- The panel *is* the button, so it gets the kit's button state machine —
	-- hover, press, and the same two cues every other clickable in the game
	-- plays. Only the two scales are ours; see the constants.
	local hover = ui.useHoverScale({
		hoverScale = HOVER_SCALE,
		pressScale = PRESS_SCALE,
	})
	-- A resolved poll unmounts the hit area, and a GuiObject destroyed under the
	-- pointer never fires MouseLeave, so `hover` alone would leave whichever panel
	-- you happened to be over lifted through the whole result.
	local hovered = hover.isHovered and not props.locked

	local isHovered = hover.isHovered
	local onLeave = hover.onLeave
	local locked = props.locked
	React.useEffect(function()
		-- Guarded on actually being hovered because `locked` flips for every panel
		-- at once: an unguarded leave would fire the whole ballot's worth of
		-- hover-out cues on the same frame as the winner. Reading `isHovered` from
		-- the render this effect belongs to is the point — the effect runs on the
		-- lock, and that render is when the pointer's position was last true.
		if locked and isHovered then
			onLeave()
		end
	end, { locked })

	local avatars: { [string]: any } = {}
	for _, userId in props.voters do
		-- Keyed by user id so a voter's stamp is the *same* element across
		-- re-renders and doesn't re-slam every time somebody else votes. Moving
		-- to another panel is a real unmount, so that does stamp again — and
		-- pressing the panel already held stamps again through `stamp`, which is
		-- the one case where nothing about the element changes but the press still
		-- has to be felt.
		avatars[`Voter{userId}`] = React.createElement(Avatar, {
			userId = userId,
			weight = props.voteWeights[userId],
			stamp = props.voteStamps[userId],
		})
	end

	-- Stroke sits inside the panel edge, so pad past it (see CLAUDE.md).
	local inset = theme.padding + theme.strokeThickness

	local children: { [string]: any } = {
		Body = React.createElement(ui.Stack, {
			gap = theme.itemSpacing,
			padding = inset,
			verticalAlignment = Enum.VerticalAlignment.Center,
			-- Leave the bottom strip to the voters so a full panel never pushes
			-- the icon or the name off-center.
			size = UDim2.new(1, 0, 1, -(AVATAR_SIZE + inset)),
		}, {
			Icon = React.createElement("ImageLabel", {
				Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Image = props.option.icon,
				ImageTransparency = if props.faded then 0.6 else 0,
				ScaleType = Enum.ScaleType.Fit,
				LayoutOrder = 1,
			}),
			Name = React.createElement(ui.Text, {
				text = props.option.name,
				textSize = theme.textSizeRegular,
				weight = Enum.FontWeight.Heavy,
				shadow = true,
				wrapped = true,
				size = UDim2.new(1, 0, 0, NAME_HEIGHT),
				layoutOrder = 2,
			}),
			Blurb = if props.option.blurb
				then React.createElement(ui.Text, {
					text = props.option.blurb,
					textSize = theme.textSizeRegular,
					color = Color3.fromRGB(196, 202, 224),
					wrapped = true,
					size = UDim2.new(1, 0, 0, BLURB_HEIGHT),
					layoutOrder = 3,
				})
				else nil,
		}),

		-- A plain frame, not a Row: the stamps place themselves (see `stampFor`),
		-- so any layout here would fight them for the position property.
		Voters = React.createElement("Frame", {
			Size = UDim2.new(1, -inset * 2, 0, AVATAR_SIZE),
			Position = UDim2.new(0.5, 0, 1, -inset),
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, avatars),
	}

	-- Transparent hit area over the whole panel: the kit has no clickable
	-- surface primitive, and the panel itself is the vote button here. Gone once
	-- the poll is resolved, so a late click can't land on a closed vote.
	if not props.locked then
		children.Hit = React.createElement("TextButton", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "",
			ZIndex = 10,
			[React.Event.MouseEnter] = hover.onEnter,
			[React.Event.MouseLeave] = hover.onLeave,
			[React.Event.MouseButton1Down] = hover.onPress,
			[React.Event.MouseButton1Up] = hover.onRelease,
			[React.Event.Activated] = props.onVote,
		})
	end

	-- Inside the panel, so it scales the panel and everything on it together.
	children.Scale = React.createElement("UIScale", {
		Scale = 1,
		ref = hover.scaleRef,
	})

	-- The slot, not the panel, is what the row measures.
	--
	-- A UIScale changes AbsoluteSize as well as what's drawn, so a panel that grew
	-- inside the layout would push its neighbours apart and the whole ballot would
	-- breathe every time the pointer crossed one. The slot holds the space at a
	-- fixed size; the panel lifts inside it and overhangs by three or four pixels,
	-- which the row's 15px gap has room for.
	return React.createElement(ui.Slot, {
		name = "Option",
		size = UDim2.fromOffset(PANEL_WIDTH, PANEL_HEIGHT),
		layoutOrder = props.layoutOrder,
		-- Over its neighbours while it's the one being pointed at, now that it
		-- overhangs them. ZIndexBehavior is Sibling, so this carries the panel and
		-- everything on it up together rather than only the slot.
		zIndex = if hovered then HOVER_ZINDEX else 1,
	}, {
		Panel = React.createElement(ui.Panel, {
			size = UDim2.fromScale(1, 1),
			transparency = if props.faded
				then LOST_TRANSPARENCY
				elseif hovered then HOVER_TRANSPARENCY
				else nil,
		}, children),
	})
end

return function(props: Props)
	local winnerId = props.winnerId
	local resolved = winnerId ~= nil and winnerId ~= ""

	local panels: { [string]: any } = {}
	for index, option in props.options do
		panels[option.id] = React.createElement(OptionPanel, {
			option = option,
			voters = props.votersByOption[option.id] or {},
			voteWeights = props.voteWeights or {},
			voteStamps = props.voteStamps or {},
			-- Once the winner is in, everything else steps back so the result is
			-- the only thing lit.
			faded = resolved and winnerId ~= option.id,
			locked = resolved,
			layoutOrder = index,
			onVote = function()
				props.onVote(option.id)
			end,
		})
	end

	local caption = `{math.ceil(props.secondsLeft)}s`
	if resolved then
		local winner = nil
		for _, option in props.options do
			if option.id == winnerId then
				winner = option
			end
		end
		caption = if winner then `{winner.name}!` else "Starting…"
	end

	local children: { [string]: any } = {
		Options = React.createElement(ui.Row, {
			gap = theme.contentSpacing,
			automaticSize = Enum.AutomaticSize.X,
			size = UDim2.new(0, 0, 0, PANEL_HEIGHT),
			layoutOrder = 1,
		}, panels),

		-- Outside the panels, under the row.
		Clock = React.createElement(ui.Text, {
			text = caption,
			textSize = theme.textSizeLarge,
			weight = Enum.FontWeight.Heavy,
			shadow = true,
			size = UDim2.new(1, 0, 0, theme.textSizeLarge + 8),
			layoutOrder = 2,
		}),
	}

	-- <UIShell.Frame> drives the enter/exit tween through a UIScale it expects to
	-- live inside the child, so the screen scales from its own center.
	if props.scaleRef then
		children.UIScale = React.createElement("UIScale", {
			Scale = props.initialScale or 1,
			ref = props.scaleRef,
		})
	end

	return React.createElement(ui.Stack, {
		gap = theme.contentSpacing,
		automaticSize = Enum.AutomaticSize.XY,
		size = UDim2.fromOffset(0, 0),
		position = UDim2.fromScale(0.5, 0.5),
		anchorPoint = Vector2.new(0.5, 0.5),
	}, children)
end
