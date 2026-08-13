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
-- simply off it. TowerGame's ballot is four (Classic plus three twists), which
-- at this width lands around 800px — comfortable on a phone in landscape.
local PANEL_WIDTH = 190
local PANEL_HEIGHT = 280
local ICON_SIZE = 78
local NAME_HEIGHT = 40
local BLURB_HEIGHT = 26
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

-- What a panel that lost fades to once the winner is in. Panel's default glass
-- is 0.8; pushing it further sinks the losers behind the winner.
local LOST_TRANSPARENCY = 0.92

export type Props = {
	-- The ballot, in display order.
	options: { Registry.Gamemode },
	-- gamemode id -> the user ids that voted for it.
	votersByOption: { [string]: { number } },
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
local function Avatar(props: { userId: number })
	local scaleRef = React.useRef(nil :: UIScale?)
	local offsetX, offsetY, rotation = stampFor(props.userId)

	React.useEffect(function()
		local scale = scaleRef.current
		if scale == nil then
			return
		end
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
	end, {})

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
	})
end

local function optionPanel(props: {
	option: Registry.Gamemode,
	voters: { number },
	faded: boolean,
	locked: boolean,
	layoutOrder: number,
	onVote: () -> (),
}): any
	local avatars: { [string]: any } = {}
	for _, userId in props.voters do
		-- Keyed by user id so a voter's stamp is the *same* element across
		-- re-renders and doesn't re-slam every time somebody else votes. Moving
		-- to another panel is a real unmount, so that does stamp again.
		avatars[`Voter{userId}`] = React.createElement(Avatar, { userId = userId })
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
				size = UDim2.new(1, 0, 0, NAME_HEIGHT),
				layoutOrder = 2,
			}),
			Blurb = if props.option.blurb
				then React.createElement(ui.Text, {
					text = props.option.blurb,
					textSize = theme.textSizeXS,
					color = Color3.fromRGB(196, 202, 224),
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
			[React.Event.Activated] = props.onVote,
		})
	end

	return React.createElement(ui.Panel, {
		size = UDim2.fromOffset(PANEL_WIDTH, PANEL_HEIGHT),
		transparency = if props.faded then LOST_TRANSPARENCY else nil,
		layoutOrder = props.layoutOrder,
	}, children)
end

return function(props: Props)
	local winnerId = props.winnerId
	local resolved = winnerId ~= nil and winnerId ~= ""

	local panels: { [string]: any } = {}
	for index, option in props.options do
		panels[option.id] = optionPanel({
			option = option,
			voters = props.votersByOption[option.id] or {},
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
