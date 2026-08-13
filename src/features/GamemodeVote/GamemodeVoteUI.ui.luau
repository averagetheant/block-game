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

local React = require(ReplicatedStorage.Packages.React)
local ui = require(ReplicatedStorage.Shared.Boil).ui
local Registry = require(script.Parent.Registry)

local theme = ui.theme

local PANEL_WIDTH = 240
local PANEL_HEIGHT = 280
local ICON_SIZE = 96
local NAME_HEIGHT = 40
local BLURB_HEIGHT = 26
local AVATAR_SIZE = 34
local AVATAR_GAP = 6

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

-- One voter: a circle with a thin stroke, small enough to sit in the panel's
-- bottom margin without crowding the content above it.
local function avatar(userId: number, layoutOrder: number): any
	return React.createElement("ImageLabel", {
		Size = UDim2.fromOffset(AVATAR_SIZE, AVATAR_SIZE),
		BackgroundColor3 = Color3.fromRGB(24, 26, 34),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Image = headshot(userId),
		LayoutOrder = layoutOrder,
	}, {
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
	for index, userId in props.voters do
		avatars[`Voter{userId}`] = avatar(userId, index)
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

		Voters = React.createElement(ui.Row, {
			gap = AVATAR_GAP,
			size = UDim2.new(1, -inset * 2, 0, AVATAR_SIZE),
			position = UDim2.new(0.5, 0, 1, -inset),
			anchorPoint = Vector2.new(0.5, 1),
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
