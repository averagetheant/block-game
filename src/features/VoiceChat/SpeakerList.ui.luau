--!strict
-- Who's talking, as a column of chips in the bottom-left corner.
--
-- One chip per live speaker: headshot, display name, and a ring around the
-- headshot that moves with their microphone. The ring is what makes the chip
-- read as *live* rather than as a roster — a static list of names in the corner
-- looks the same whether the voice is working or not.
--
-- No surface behind a chip and no box around one. This is ambient — it appears
-- while someone talks and is gone a moment later — and a panel per speaker would
-- stack boxes in the corner for something nobody clicks. The avatar ring and the
-- text's own outline carry it against the world instead.
--
-- Dumb by construction (see docs/game/headless-core.md): everything it draws
-- arrives as props. VoiceView hands it the speakers; the story hands it fakes.
--
-- The column sizes itself to its contents, so anchored by its bottom-left
-- corner (which is what VoiceView and the story both do) it grows *upward* —
-- chips appear above the ones already there instead of moving the corner.
--
-- The ring is animated by writing to the UIStroke directly rather than through
-- state, the same call TurnStrip makes: a level that re-rendered the tree at
-- speech rate would re-render the HUD's corner sixty times a second to move one
-- outline. React owns *which* chips exist; the effect owns how loud each is.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage.Packages.React)
local ui = require(ReplicatedStorage.Shared.Boil).ui
local Constants = require(script.Parent.Constants)

export type Speaker = {
	userId: number,
	displayName: string,
}

export type Props = {
	-- Everyone currently talking, longest-running first. Past MAX_SHOWN the
	-- overflow is reported as a count rather than drawn.
	speakers: { Speaker },
	-- A speaker's microphone level, 0-1. Optional: without it every ring sits at
	-- rest, which is what the story does when its slider is at zero.
	levelOf: ((userId: number) -> number)?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
}

-- Roblox resolves this to the player's headshot without a web call from us.
local function headshot(userId: number): string
	return `rbxthumb://type=AvatarHeadShot&id={userId}&w=150&h=150`
end

-- Display names run to 20 characters and a chip is read at a glance, so the long
-- ones are cut rather than shrunk — a smaller font for one name would make the
-- column ragged. Graphemes rather than bytes: a name can be emoji or CJK, and
-- cutting those by byte produces mojibake.
local function shorten(name: string): string
	local kept = {}
	local count = 0
	for first, last in utf8.graphemes(name) do
		count += 1
		if count > Constants.NAME_MAX_CHARS then
			return table.concat(kept) .. "…"
		end
		table.insert(kept, string.sub(name, first, last))
	end
	return name
end

-- One speaker. The headshot's ring follows their level; everything else is
-- static for as long as the chip is up.
local function SpeakerChip(props: {
	speaker: Speaker,
	levelOf: ((userId: number) -> number)?,
	layoutOrder: number,
})
	local strokeRef = React.useRef(nil :: UIStroke?)
	local userId = props.speaker.userId
	local levelOf = props.levelOf
	-- Where the name starts: past the avatar, one gap clear of it. No panel to
	-- inset from, so this is the only spacing the chip has.
	local nameX = Constants.AVATAR_SIZE + ui.theme.itemSpacing

	React.useEffect(function()
		local stroke = strokeRef.current
		if stroke == nil or levelOf == nil then
			return
		end

		-- Chased rather than set: the sampled level steps at the poll rate, and
		-- a ring that stepped with it would strobe on every consonant.
		local shown = 0
		local connection = RunService.RenderStepped:Connect(function(deltaTime: number)
			local target = levelOf(userId)
			shown += (target - shown) * math.min(deltaTime * Constants.LEVEL_FOLLOW, 1)
			stroke.Thickness = Constants.RING_MIN + (Constants.RING_MAX - Constants.RING_MIN) * shown
		end)

		return function()
			connection:Disconnect()
		end
	end, { userId, levelOf } :: { any })

	return React.createElement("Frame", {
		Size = UDim2.fromOffset(Constants.CHIP_WIDTH, Constants.CHIP_HEIGHT),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder,
	}, {
		Avatar = React.createElement("ImageLabel", {
			Image = headshot(userId),
			Size = UDim2.fromOffset(Constants.AVATAR_SIZE, Constants.AVATAR_SIZE),
			Position = UDim2.new(0, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = Color3.fromRGB(24, 26, 34),
			BorderSizePixel = 0,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
			Ring = React.createElement("UIStroke", {
				ref = strokeRef,
				Thickness = Constants.RING_MIN,
				Color = Constants.RING_COLOR,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
		}),

		-- Text's own outline is doing the work a panel used to: the name sits
		-- straight on the sky, and white-on-cloud without it is unreadable.
		Name = React.createElement(ui.Text, {
			text = shorten(props.speaker.displayName),
			textSize = ui.theme.textSizeSmall,
			xAlignment = Enum.TextXAlignment.Left,
			size = UDim2.new(1, -nameX, 1, 0),
			position = UDim2.new(0, nameX, 0, 0),
		}),
	})
end

return function(props: Props)
	local speakers = props.speakers
	local children: { [string]: any } = {}

	-- The most recent talkers, oldest of those at the top. Trimmed from the
	-- front rather than the back so somebody who just started is always on
	-- screen — in a full server the alternative is a column of four people who
	-- happened to speak first, and the person talking now never appearing.
	local first = math.max(#speakers - Constants.MAX_SHOWN + 1, 1)
	for index = first, #speakers do
		local speaker = speakers[index]
		-- Keyed by user id so a chip survives the ones above it going away,
		-- which is what keeps its ring animating instead of restarting.
		children[`Speaker{speaker.userId}`] = React.createElement(SpeakerChip, {
			speaker = speaker,
			levelOf = props.levelOf,
			layoutOrder = index,
		})
	end

	local hidden = first - 1
	if hidden > 0 then
		children.Overflow = React.createElement(ui.Text, {
			text = `+{hidden} more talking`,
			textSize = ui.theme.textSizeXS,
			xAlignment = Enum.TextXAlignment.Left,
			size = UDim2.fromOffset(Constants.CHIP_WIDTH, ui.theme.textSizeXS + 4),
			-- Below the chips: it's a footnote to the column, and the column is
			-- read from the corner upward.
			layoutOrder = #speakers + 1,
		})
	end

	-- Sized to its contents on Y, so with a bottom-left anchor the column grows
	-- *upward* out of the corner: a new chip appears above the ones already
	-- there rather than shoving the first one off the edge.
	return React.createElement(ui.Stack, {
		gap = Constants.CHIP_GAP,
		horizontalAlignment = Enum.HorizontalAlignment.Left,
		verticalAlignment = Enum.VerticalAlignment.Bottom,
		size = props.size or UDim2.fromOffset(Constants.CHIP_WIDTH, 0),
		automaticSize = Enum.AutomaticSize.Y,
		position = props.position,
		anchorPoint = props.anchorPoint,
		layoutOrder = props.layoutOrder,
		zIndex = props.zIndex,
		children = children,
	})
end
