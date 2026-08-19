--!strict
-- Pure/dumb HUD for the PVP round. Takes the whole match as props and renders it;
-- owns no data fetching, no networking, no clock. `PvpView` wires it to the
-- controller store, and `PvpHUD.story` drives it from sliders in UI Labs.
--
-- It replaces the classic HUD rather than sitting beside it: everything that one
-- draws is about a turn queue and a storm, and neither exists here.
--
--   top center     one bar — the match clock and your place — with the zone
--                  reel under it
--   right edge     the height rail: a headshot per lane, riding at the height
--                  that lane has reached, yours lit and carrying the one
--                  reading in studs
--   right, above   the map toggle (the classic HUD's camera button, doing the
--   the corner     PVP job: show the whole board instead of your own lane)
--   bottom left    controls hint (fades out on its own)
--   bottom center  touch controls (touch devices only)
--   center         the countdown, then the final standings
--
-- Layout note: a full-screen gameplay HUD, so it hugs the edges rather than
-- following the centered-by-default rule for feature UIs. The two things that
-- *are* centred are the two that own the moment rather than annotate it — the
-- countdown and the results — and both are up while nothing is being aimed.
--
-- **One surface per corner.** The clock and the stats line used to be two
-- stacked panels, each with its own outline, which put a two-storey slab of grey
-- over the middle of the sky the towers grow into. They're one line now — the
-- clock and your place — in one panel.
--
-- **The live standings are a rail, not a table.** A 268-wide board of six rows
-- spent the right third of the sky answering "by how many studs?", which is a
-- question nobody asks with a piece in the air. `HeightRail` answers the one
-- they do ask — am I ahead, and of whom — as a column of faces on a shared
-- scale, 52 wide. The *final* standings are still a table: the match is over,
-- nothing is being aimed, and by then the exact number is the point.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Boil = require(ReplicatedStorage.Shared.Boil)
local ui = Boil.ui
local Constants = require(script.Parent.Constants)
local ControlsHint = require(script.Parent.ControlsHint)
local HeightRail = require(script.Parent.HeightRail)
local PvpConstants = require(script.Parent.PvpConstants)
local RadialTimer = require(script.Parent.RadialTimer)
local SteerStick = require(script.Parent.SteerStick)
local ZoneReel = require(script.Parent.ZoneReel)

local PHASE = PvpConstants.PHASE

-- Shared with the classic HUD so the two can't disagree about where the screen
-- ends — a player switching modes between rounds should see things stay put.
local EDGE_MARGIN = Constants.EDGE_MARGIN
-- Only the height, and only to stack the camera toggle above the counter. The
-- counter itself is its own root on the flourish layer (see `TowerCashView`), so
-- a payout lands in front of whatever window the player was in — neither HUD
-- draws it any more.
local CASH_HEIGHT = Constants.CASH_HEIGHT
local TOP_MARGIN = 10
local STACK_GAP = 6

-- The top bar: one line — the match clock, with your place beside it. Your own
-- height used to be its left third; it rides the rail's marker now, for the
-- reason the classic HUD moved its readout onto the climb line — how high your
-- tower is and where that puts you on the rail are the same fact, and answering
-- it twice is two places for it to disagree.
local COLUMN_WIDTH = 360
local BAR_PAD = 6
local BAR_ROW = 52
local CLOCK_TEXT_SIZE = 44
local STAT_TEXT_SIZE = 22
local BAR_HEIGHT = BAR_PAD * 2 + BAR_ROW
-- The box the place readout is drawn in, off the right end of the bar. The clock
-- is centred on the panel rather than laid out beside it, so this is the ordinal
-- alone and doesn't have to be balanced by anything on the left.
local RANK_WIDTH = 120

local CONTROL_GAP = 12
local CONTROL_ROW_HEIGHT = 88
local CONTROL_ROW_WIDTH = Constants.STICK_TRACK_WIDTH + 110 + 160 + CONTROL_GAP * 4
local BUTTON_SIZE = UDim2.fromOffset(110, 88)
local DROP_SIZE = UDim2.fromOffset(160, 88)

local CAMERA_BUTTON = 62
-- The drop clock's dial, flanking the top bar the same way the classic turn dial
-- flanks the turn strip — outside it, so a piece being dealt can never move the
-- readout beside it.
local DIAL_SIZE = 74
local FLANK_Y = TOP_MARGIN + BAR_HEIGHT / 2

-- The height rail, down the right edge. The classic HUD's climb-rail geometry
-- exactly — same inset, same top, same clearance over the corner — because it's
-- the same furniture doing this mode's version of the same job, and a player
-- switching modes between rounds shouldn't have to find it again.
--
-- Inset from the edge rather than flush to it because the reactions column opens
-- down that edge, vertically centred. Hardcoded rather than read from that
-- feature's constants: a feature can't name another feature, and the rail only
-- needs to be clear of it.
local RAIL_RIGHT = 96
-- Clear of Roblox's own topbar, which owns the top strip at the true top of the
-- display (the root ScreenGui sets IgnoreGuiInset, so y = 0 really is the top).
local RAIL_TOP = 84
-- Clear of the camera toggle and the cash counter stacked in the corner below.
local RAIL_BOTTOM = CASH_HEIGHT + CAMERA_BUTTON + EDGE_MARGIN * 3
-- Wide enough for the rail's own widest marker; it has to agree with RAIL_WIDTH
-- in `HeightRail`. Stated here rather than read from there for the same reason
-- the classic HUD states its own: the component owns how wide a face is, the HUD
-- owns how much of the screen edge it hands over, and the two meet at a number.
local RAIL_WIDTH = 52
-- The whole band between the topbar and the corner, rather than a fixed height.
-- The canvas is 720 units tall at 16:9 and about 2100 on a portrait phone — the
-- same fixed rail would fill the first screen and sit in the top fifth of the
-- second with nothing under it. Filling the band is both the biggest the rail can
-- be and, since the margins at either end are close to equal, centred in it.

local COUNTDOWN_TEXT_SIZE = 130

-- The final standings. The winner's row is taller than the rest because the
-- match asked one question and that row is the answer to it.
local RESULTS_WIDTH = 520
local RESULTS_TITLE = 46
local RESULTS_TITLE_TEXT = 34
local RESULTS_ROW = 50
local RESULTS_WINNER_ROW = 68
local RESULTS_GAP = 6

-- Under this many seconds the match clock turns red. A quarter of the match is
-- too early to panic and ten seconds is too late to change anything.
local URGENT_SECONDS = 30

local YOU_COLOR = Color3.fromRGB(255, 214, 110)
local MUTED_COLOR = Color3.fromRGB(184, 192, 214)
local URGENT_COLOR = Color3.fromRGB(255, 138, 122)
-- The drop dial's two states, matched to the classic turn dial's so a player
-- reads "green is fine, red is now" the same way in both modes.
local DIAL_COLOR = Color3.fromRGB(112, 214, 122)
local DIAL_URGENT_COLOR = Color3.fromRGB(232, 96, 96)
-- Under this many seconds on the drop clock the dial turns red.
local DIAL_URGENT_SECONDS = 5

-- Gold, silver, bronze; everything past third draws in the ordinary colour.
local PLACE_COLORS = {
	Color3.fromRGB(255, 214, 110),
	Color3.fromRGB(214, 222, 240),
	Color3.fromRGB(226, 158, 106),
}
-- The rank disc: a medal for the top three, a plain dark one after that. The
-- number on a medal is drawn in ink rather than white — white on gold at this
-- size is a smear.
local CHIP_DARK = Color3.fromRGB(38, 42, 58)
local CHIP_INK = Color3.fromRGB(20, 22, 32)
-- Row fills. Every row is drawn on the results panel's own glass rather than in
-- a panel of its own: six nested panels, each with its own 4px outline, is what
-- made the old board read as a spreadsheet.
local ROW_FILL = Color3.fromRGB(16, 18, 28)
local ROW_TRANSPARENCY = 0.5
local YOU_TRANSPARENCY = 0.8
-- The winner's row on the results board, washed in the gold of its own medal.
-- Denser than YOU_TRANSPARENCY on purpose: when the two rows are on screen
-- together the winner has to be the one the eye lands on first.
local WINNER_TRANSPARENCY = 0.55

export type Entry = {
	userId: number,
	-- Resolved on the client, because a name resolved from a user id is one the
	-- player it belongs to can't have made up.
	name: string,
	height: number,
}

export type Props = {
	phase: number,
	-- Seconds left on whichever clock the phase is running.
	secondsLeft: number,
	matchSeconds: number,
	-- The zone that's up — or, while `zoneRolling` is true, the one that's about
	-- to be. The reel owns the difference; see `ZoneReel`.
	zoneId: number,
	zoneRolling: boolean?,
	-- Every lane, tallest first.
	standings: { Entry },
	-- This player's place, or 0 when they aren't in the match (spectating, or
	-- every seat was taken when they arrived). It's the whole of what the HUD
	-- knows about them: their own height used to ride beside it as `myHeight`,
	-- and now comes off their row in `standings` where the rail draws it, so the
	-- face and the number can't be fed two different readings.
	myRank: number,
	-- Whether they're aiming a piece, what it is, and how long they have.
	holding: boolean,
	pieceName: string,
	pieceSecondsLeft: number,
	device: ControlsHint.Device,
	showControls: boolean?,
	showHint: boolean?,
	-- Whether the camera is showing the whole board. Only colours the button —
	-- the camera controller owns the state.
	overview: boolean?,
	onToggleCamera: (() -> ())?,
	onSteer: ((value: number) -> ())?,
	onRotate: (() -> ())?,
	onDrop: (() -> ())?,
}

local function clock(seconds: number): string
	local whole = math.max(math.ceil(seconds), 0)
	return string.format("%d:%02d", whole // 60, whole % 60)
end

local function ordinal(rank: number): string
	if rank <= 0 then
		return "—"
	end
	local suffix = "th"
	-- 11th, 12th and 13th are the exceptions the last-digit rule gets wrong. A
	-- six-player match can't reach them, but the function shouldn't be the thing
	-- that breaks if the lane cap ever moves.
	if rank % 100 < 11 or rank % 100 > 13 then
		local last = rank % 10
		suffix = if last == 1 then "st" elseif last == 2 then "nd" elseif last == 3 then "rd" else "th"
	end
	return `{rank}{suffix}`
end

-- Roblox resolves this to the player's headshot without a web call from us. The
-- same form the classic HUD's turn strip uses, so a face is a face in both modes.
local function headshot(userId: number): string
	return `rbxthumb://type=AvatarHeadShot&id={userId}&w=150&h=150`
end

-- A face. Raw ImageLabel for the reason TurnStrip gives: the UI kit has no avatar
-- component, and an avatar chip is game content rather than a primitive worth
-- adding to the contract.
local function avatar(userId: number, size: number, order: number)
	return React.createElement("ImageLabel", {
		Image = headshot(userId),
		BackgroundColor3 = CHIP_DARK,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(size, size),
		LayoutOrder = order,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Stroke = React.createElement("UIStroke", {
			Thickness = 2,
			Color = CHIP_INK,
			Transparency = 0.4,
		}),
	})
end

-- The place, as a disc.
local function medal(rank: number, size: number, order: number)
	local colour = PLACE_COLORS[rank]
	return React.createElement("Frame", {
		BackgroundColor3 = colour or CHIP_DARK,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(size, size),
		LayoutOrder = order,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Stroke = React.createElement("UIStroke", {
			Thickness = 2,
			Color = CHIP_INK,
			Transparency = 0.3,
		}),
		Number = React.createElement(ui.Text, {
			text = tostring(rank),
			-- Sized off the disc, so the two can't drift apart.
			textSize = math.floor(size * 0.6),
			weight = Enum.FontWeight.Heavy,
			color = if colour then CHIP_INK else MUTED_COLOR,
			-- No outline. `ui.Text` draws a dark miter stroke by default, which is
			-- what makes white text readable over anything — but a dark digit on a
			-- gold disc with a dark outline around it is a blob, not a number.
			strokeThickness = 0,
			xAlignment = Enum.TextXAlignment.Center,
			size = UDim2.fromScale(1, 1),
		}),
	})
end

-- One row on either board: a rounded fill and whatever the caller puts in it.
--
-- A plain Frame rather than a Panel, because the board around it already draws
-- the glass and the outline and a panel per row drew six more of each.
--
-- `accent` is your own row — a gold edge down its left side and a gold wash
-- behind it. It replaced painting the whole row in the yellow gem surface, which
-- at row height swamped the name it was supposed to be pointing at.
local function row(props: {
	height: number,
	accent: boolean,
	order: number,
	-- Overrides the fill for a row that isn't "yours" but still isn't ordinary —
	-- the winner's, on the results board.
	fill: Color3?,
	transparency: number?,
	children: { [string]: any },
})
	local children: { [string]: any } = {
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 8) }),
	}
	if props.accent then
		children.Accent = React.createElement("Frame", {
			BackgroundColor3 = YOU_COLOR,
			BorderSizePixel = 0,
			Size = UDim2.new(0, 4, 1, -10),
			Position = UDim2.new(0, 3, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			ZIndex = 2,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
		})
	end
	for key, child in props.children do
		children[key] = child
	end

	return React.createElement("Frame", {
		BackgroundColor3 = props.fill or (if props.accent then YOU_COLOR else ROW_FILL),
		BackgroundTransparency = props.transparency
			or (if props.accent then YOU_TRANSPARENCY else ROW_TRANSPARENCY),
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, props.height),
		LayoutOrder = props.order,
	}, children)
end

-- One row of the final standings. The winner's is taller, gold, and says what it
-- is; the rest are the same row a size down.
local function resultRow(entry: Entry, rank: number, you: boolean)
	local winner = rank == 1
	return row({
		height = if winner then RESULTS_WINNER_ROW else RESULTS_ROW,
		accent = you and not winner,
		order = rank,
		-- The top row is washed gold rather than merely bigger. Your own row is
		-- washed too, and a shade lighter — read together, the board says "this
		-- one won, that one is you", in that order.
		fill = if winner then PLACE_COLORS[1] else nil,
		transparency = if winner then WINNER_TRANSPARENCY else nil,
		children = {
			Row = React.createElement(ui.Row, {
				size = UDim2.fromScale(1, 1),
				gap = 12,
				padding = 10,
			}, {
				Place = medal(rank, if winner then 40 else 32, 1),
				Face = avatar(entry.userId, if winner then 46 else 34, 2),
				Name = React.createElement(ui.Text, {
					text = entry.name,
					textSize = if winner then 32 else 26,
					weight = Enum.FontWeight.Heavy,
					color = if winner then PLACE_COLORS[1] elseif you then YOU_COLOR else nil,
					shadow = true,
					xAlignment = Enum.TextXAlignment.Left,
					fit = true,
					minTextSize = 18,
					size = UDim2.new(1, -(if winner then 330 else 244), 1, 0),
					layoutOrder = 3,
				}),
				-- The winner's row says what it won on the way past. Every other
				-- row is a height and a place, which is all there is to say.
				Tag = if winner
					then React.createElement(ui.Text, {
						-- Second person when it's you, because "WINNER" beside your
						-- own name is a caption and "YOU WIN!" is the point of the
						-- last three minutes.
						text = if you then "YOU WIN!" else "WINNER",
						textSize = 20,
						weight = Enum.FontWeight.Heavy,
						color = PLACE_COLORS[1],
						xAlignment = Enum.TextXAlignment.Right,
						size = UDim2.new(0, 82, 1, 0),
						layoutOrder = 4,
					})
					else nil,
				Height = React.createElement(ui.Text, {
					text = `{string.format("%.1f", entry.height)} studs`,
					textSize = if winner then 30 else 26,
					weight = Enum.FontWeight.Heavy,
					shadow = true,
					xAlignment = Enum.TextXAlignment.Right,
					size = UDim2.new(0, 140, 1, 0),
					layoutOrder = 5,
				}),
			}),
		},
	})
end

-- The centred moment: a countdown before the first piece, the final standings
-- after the last one. Only one is ever up, and never while anything is being
-- aimed — which is what lets both sit dead centre over the towers.
local function centrepiece(props: Props)
	if props.phase == PHASE.COUNTDOWN then
		return React.createElement(ui.Text, {
			text = tostring(math.max(math.ceil(props.secondsLeft), 1)),
			textSize = COUNTDOWN_TEXT_SIZE,
			weight = Enum.FontWeight.Heavy,
			shadow = true,
			xAlignment = Enum.TextXAlignment.Center,
			size = UDim2.fromOffset(300, 180),
			position = UDim2.fromScale(0.5, 0.5),
			anchorPoint = Vector2.new(0.5, 0.5),
		})
	end

	if props.phase ~= PHASE.RESULTS then
		return nil
	end

	local rows: { [string]: any } = {
		Title = React.createElement(ui.Text, {
			text = "FINAL HEIGHTS",
			textSize = RESULTS_TITLE_TEXT,
			weight = Enum.FontWeight.Heavy,
			shadow = true,
			xAlignment = Enum.TextXAlignment.Center,
			size = UDim2.new(1, 0, 0, RESULTS_TITLE),
			layoutOrder = 0,
		}),
	}
	local userId = Players.LocalPlayer.UserId
	for rank, entry in props.standings do
		rows[`Row{rank}`] = resultRow(entry, rank, entry.userId == userId)
	end

	-- Measured rather than automatic, and this is the bug that measurement fixes:
	-- `ui.Panel` draws a fixed-size surface, so a panel handed height 0 with an
	-- auto-sizing list inside it painted a sliver of glass and let every row hang
	-- off the bottom of it, unbacked, over the towers. The list and the surface
	-- are sized off the same arithmetic now.
	-- Plain padding, not `padding + strokeThickness` like every other surface in
	-- here: that sum exists to stop content crowding an outline, and this panel
	-- has none. Adding it anyway would inset the rows by the width of a stroke
	-- that isn't drawn.
	local pad = ui.theme.padding
	local count = #props.standings
	local rowsHeight = if count > 0
		then RESULTS_WINNER_ROW + (count - 1) * (RESULTS_ROW + RESULTS_GAP) + RESULTS_GAP
		else 0
	local panelHeight = pad * 2 + RESULTS_TITLE + rowsHeight

	-- Rounded and outline-less, unlike every other surface in this HUD. The rest
	-- are chrome sitting at the edges of the screen and their outlines are what
	-- hold them apart from the sky; this one lands dead centre with the match
	-- over, nothing is being aimed behind it, and it's the last thing anyone
	-- looks at. A hard-cornered outline makes that read as one more panel.
	return React.createElement(ui.Panel, {
		size = UDim2.fromOffset(RESULTS_WIDTH, panelHeight),
		position = UDim2.fromScale(0.5, 0.5),
		anchorPoint = Vector2.new(0.5, 0.5),
		rounded = true,
		stroke = false,
	}, {
		List = React.createElement(ui.Stack, {
			size = UDim2.fromScale(1, 1),
			gap = RESULTS_GAP,
			padding = pad,
			verticalAlignment = Enum.VerticalAlignment.Top,
		}, rows),
	})
end

return function(props: Props)
	-- A place of 0 is the server saying this player has no lane — `myRank` is
	-- found by looking them up in the same list the rail is drawn from, so the
	-- two can't disagree about whether they're in the match.
	local playing = props.myRank > 0
	local canAct = props.holding and props.phase == PHASE.PLAYING
	-- Once the clock stops, the results board says everything the top bar and the
	-- live board were saying — so both go, and the last ten seconds are the towers
	-- with one panel over them.
	local live = props.phase ~= PHASE.RESULTS

	local children: { [string]: any } = {
		-- Shows the whole board instead of your own lane. The same button, in the
		-- same corner, as the classic HUD's overview toggle — it answers the same
		-- question ("show me more than I'm building on"), and a player who has
		-- learned where it lives shouldn't have to learn again per mode.
		CameraToggle = React.createElement(ui.IconButton, {
			icon = ui.assets.Icons.magnifyingGlass,
			variant = if props.overview then "green" else "blue",
			size = UDim2.fromOffset(CAMERA_BUTTON, CAMERA_BUTTON),
			-- Stacked above the counter, the same way and by the same arithmetic
			-- as the classic HUD's. A match pays out at the results panel, so the
			-- corner has to hold both.
			position = UDim2.new(1, -EDGE_MARGIN, 1, -(CASH_HEIGHT + EDGE_MARGIN * 2)),
			anchorPoint = Vector2.new(1, 1),
			onClick = props.onToggleCamera,
		}),
	}

	if live then
		children.Column = React.createElement(ui.Stack, {
			gap = STACK_GAP,
			size = UDim2.fromOffset(COLUMN_WIDTH, 0),
			automaticSize = Enum.AutomaticSize.Y,
			position = UDim2.new(0.5, 0, 0, TOP_MARGIN),
			anchorPoint = Vector2.new(0.5, 0),
		}, {
			Bar = React.createElement(ui.Panel, {
				size = UDim2.new(1, 0, 0, BAR_HEIGHT),
				layoutOrder = 1,
			}, {
				-- The clock, dead centre of the panel and twice the tier of the
				-- place beside it: it's the number read constantly, the place is
				-- what you check between pieces. Centred on the panel rather than
				-- laid out in a row, so losing the height cell to the rail moved
				-- nothing — the clock was already where it is now.
				Time = React.createElement(ui.Text, {
					-- The countdown phase counts *itself* down in the centre of the
					-- screen, so the clock up here shows the match that's about to
					-- start rather than a second number racing the first.
					text = if props.phase == PHASE.COUNTDOWN
						then clock(props.matchSeconds)
						else clock(props.secondsLeft),
					textSize = CLOCK_TEXT_SIZE,
					weight = Enum.FontWeight.Heavy,
					shadow = true,
					color = if props.phase == PHASE.PLAYING and props.secondsLeft <= URGENT_SECONDS
						then URGENT_COLOR
						else nil,
					xAlignment = Enum.TextXAlignment.Center,
					-- The whole bar, and the place is drawn over the right end of
					-- it rather than beside it. "2:14" at this tier is about a
					-- third of the panel and centred in it, so the two never meet
					-- — and giving the clock a box that stopped short of the place
					-- would move the clock instead, which is the one readout on
					-- this HUD that has to stay put.
					size = UDim2.new(1, -(BAR_PAD + ui.theme.strokeThickness) * 2, 1, 0),
					position = UDim2.fromScale(0.5, 0.5),
					anchorPoint = Vector2.new(0.5, 0.5),
				}),
				-- Your place — or, for somebody with no lane, the fact that they
				-- haven't got one. "Watching" rather than a blank, because an
				-- empty corner reads as a HUD that failed to fill rather than as
				-- an answer.
				Rank = React.createElement(ui.Text, {
					text = if playing then ordinal(props.myRank) else "Watching",
					textSize = STAT_TEXT_SIZE,
					weight = Enum.FontWeight.Heavy,
					color = if playing then PLACE_COLORS[props.myRank] or MUTED_COLOR else MUTED_COLOR,
					xAlignment = Enum.TextXAlignment.Right,
					fit = true,
					minTextSize = 16,
					size = UDim2.new(0, RANK_WIDTH, 1, 0),
					-- Inset past the panel's own stroke, not just to it: a readout
					-- laid flush against a 4px outline crowds it however right the
					-- number is.
					position = UDim2.new(1, -(BAR_PAD + ui.theme.strokeThickness), 0.5, 0),
					anchorPoint = Vector2.new(1, 0.5),
				}),
			}),

			-- The zone, and the only animated thing in the column. It keeps the row
			-- height it had as a plain label, so the readouts above it never move —
			-- the description card grows *downwards*, off the bottom of the column,
			-- where there is nothing to push around.
			Zone = React.createElement(ZoneReel, {
				zoneId = props.zoneId,
				rolling = props.zoneRolling,
				width = COLUMN_WIDTH,
				restColor = MUTED_COLOR,
				layoutOrder = 2,
			}),
		})

		-- Every lane on one scale, down the right edge. It replaces the standings
		-- board wholesale: same information, a fifth of the width, and it reads at
		-- a glance instead of asking to be scanned row by row.
		children.Rail = React.createElement(HeightRail, {
			entries = props.standings,
			-- nil while spectating, which is what draws the rail with no reading
			-- and no trail on it rather than lighting somebody else's face.
			youUserId = if playing then Players.LocalPlayer.UserId else nil,
			size = UDim2.new(0, RAIL_WIDTH, 1, -(RAIL_TOP + RAIL_BOTTOM)),
			position = UDim2.new(1, -RAIL_RIGHT, 0, RAIL_TOP),
			anchorPoint = Vector2.new(1, 0),
		})
	end

	-- The piece being aimed, named at the bottom where the player is already
	-- looking when they're about to place. Nothing to say between pieces.
	if canAct then
		children.Status = React.createElement(ui.Text, {
			text = props.pieceName,
			textSize = ui.theme.textSizeRegular,
			weight = Enum.FontWeight.Bold,
			shadow = true,
			xAlignment = Enum.TextXAlignment.Center,
			size = UDim2.new(0, COLUMN_WIDTH, 0, ui.theme.textSizeRegular + 8),
			position = UDim2.new(
				0.5,
				0,
				1,
				-(if props.showControls then CONTROL_ROW_HEIGHT + EDGE_MARGIN * 2 else EDGE_MARGIN)
			),
			anchorPoint = Vector2.new(0.5, 1),
		})

		-- The drop clock, flanking the bar rather than sitting in it — same rule as
		-- the classic dial, and for the same reason: a dial that comes and goes
		-- with every piece must not be able to resize the readout beside it.
		children.Dial = React.createElement(RadialTimer, {
			progress = math.clamp(props.pieceSecondsLeft / math.max(PvpConstants.PIECE_SECONDS, 1), 0, 1),
			label = tostring(math.max(math.ceil(props.pieceSecondsLeft), 0)),
			color = if props.pieceSecondsLeft <= DIAL_URGENT_SECONDS then DIAL_URGENT_COLOR else DIAL_COLOR,
			size = DIAL_SIZE,
			position = UDim2.new(0.5, COLUMN_WIDTH / 2 + EDGE_MARGIN + DIAL_SIZE / 2, 0, FLANK_Y),
			anchorPoint = Vector2.new(0.5, 0.5),
		})
	end

	-- Opt-out rather than opt-in, matching the classic HUD: the hint fades itself
	-- out after HINT_SECONDS, so "show it" is the right default and the flag
	-- exists for the story.
	if props.showHint ~= false then
		children.Hint = React.createElement(ControlsHint, {
			device = props.device,
			-- Bottom-left, where the classic HUD puts it. Passing neither left it
			-- at the frame's origin, which is the top-left corner — under Roblox's
			-- own topbar and nowhere near where a player who has been through a
			-- classic round is looking.
			position = UDim2.new(0, EDGE_MARGIN, 1, -EDGE_MARGIN),
			anchorPoint = Vector2.new(0, 1),
		})
	end

	-- Touch controls. Rendered by the view only on touch-without-keyboard devices,
	-- and greyed out rather than unmounted between pieces so the row doesn't
	-- appear and disappear under the player's thumbs.
	if props.showControls then
		children.Controls = React.createElement(ui.Row, {
			gap = CONTROL_GAP,
			size = UDim2.fromOffset(CONTROL_ROW_WIDTH, CONTROL_ROW_HEIGHT),
			position = UDim2.new(0.5, 0, 1, -EDGE_MARGIN),
			anchorPoint = Vector2.new(0.5, 1),
		}, {
			Stick = React.createElement(SteerStick, {
				disabled = not canAct,
				onSteer = props.onSteer or function() end,
				layoutOrder = 1,
			}),
			Turn = React.createElement(ui.Button, {
				text = "TURN",
				variant = "purple",
				size = BUTTON_SIZE,
				disabled = not canAct,
				onClick = props.onRotate,
				layoutOrder = 2,
			}),
			Drop = React.createElement(ui.Button, {
				text = "DROP",
				variant = "red",
				size = DROP_SIZE,
				disabled = not canAct,
				onClick = props.onDrop,
				layoutOrder = 3,
			}),
		})
	end

	children.Centre = centrepiece(props)

	return React.createElement("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, children)
end
