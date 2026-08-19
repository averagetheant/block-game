--!strict
-- The zone reel: how a PVP match tells you the weather is about to change, and
-- then what it changed to.
--
-- The server rolls the next zone a couple of seconds *before* it takes effect
-- (`PvpConstants.ZONE_ROLL_SECONDS`) and puts the moment it lands on the wire.
-- This is what fills that window: the name flicks through the zone list, slowing
-- as it goes, and stops on the one that actually rolled at the same instant the
-- sky changes. Then it says what that zone does to the game, and gets out of the
-- way again.
--
-- The line is the point as much as the spin is. "Snowy Zone" is a name a player
-- learns by losing a tower to it; "blocks are slippery" is the same lesson, given
-- before the tower falls rather than after. The classic run has the warning banner
-- for this (see `TowerHUD`); a match had nothing but a name.
--
-- It is the *same* line the banner shows: the zone's `warning`. It used to be a
-- longer `description` field written per surface, which meant a zone told a
-- player one thing in a classic round and another in a match.
--
-- Dumb by construction: `rolling` is the entire animation clock. This file never
-- reads the match state, a packet or a server stamp — `PvpView` owns that and
-- hands down a boolean.
--
-- Yes, the answer is on the wire the whole time the reel is spinning. That isn't
-- a spoiler that matters: nothing in the world changes until the reel lands (both
-- realms hold off for the same window), so there is nothing to act on early, and
-- a client that read ahead would only be spoiling its own surprise.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ui = require(ReplicatedStorage.Shared.Boil).ui

local Zones = require(script.Parent.Zones)

-- The name row keeps the height it has at rest whether the reel is spinning or
-- not, so a roll never shoves the HUD column around underneath it.
local NAME_TEXT_SIZE = ui.theme.textSizeRegular
local NAME_HEIGHT = NAME_TEXT_SIZE + 8

local DETAIL_TEXT_SIZE = ui.theme.textSizeSmall
-- Two lines is what the longest line in `Zones.luau` fits in at this width. The
-- card holds that height rather than sizing to its text: a card that grew a line
-- for one zone would move the reel above it as it landed. The warnings are mostly
-- one line, so the card usually has room to spare — which is the right way round.
local DETAIL_LINE_HEIGHT = 30
local DETAIL_LINES = 2

-- The flick. Starts fast and eases out multiplicatively, so the reel is visibly
-- slowing when the answer arrives — but never actually stops on its own, because
-- a reel that ran out of momentum before the window closed would read as frozen.
-- The stop is the landing, not the end of the animation.
local REEL_FIRST_STEP = 0.05
local REEL_LAST_STEP = 0.2
local REEL_SLOWDOWN = 1.22

-- How long the line stays up after the reel lands.
--
-- Ten, not the five it opened at: five is long enough to read a line you already
-- know and short of long enough to read one you don't, and a player meeting Ghost
-- or Space for the first time is exactly who the card is for. Still under a third
-- of the zone's own 35 seconds, so it is well gone before the zone is.
local DETAIL_SECONDS = 10

-- The landing. Back/Out overshoots slightly, which is the "clunk" that makes the
-- name read as having *stopped* rather than as having faded in.
local LAND_TWEEN = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SPIN_SCALE = 0.88

export type Props = {
	-- The zone that rolled. Shown once the reel lands; while it is spinning the
	-- reel shows everything *but* the answer.
	zoneId: number,
	-- Whether the roll window is still open. The whole animation hangs off this.
	rolling: boolean?,
	-- Width the description card is drawn at. The name row fills its parent.
	width: number,
	layoutOrder: number?,
	-- Colour the name rests in once the news is old. nil keeps it in the zone's
	-- own tint, which is the right default anywhere the reel is not sitting in a
	-- column of muted readouts (it is, in the PVP HUD — see `PvpHUD`).
	restColor: Color3?,
}

-- Which name the reel is showing, and whether the description is up.
--
-- Two pieces of state and one effect, keyed on the roll: spinning while the
-- window is open, landed and talking for a few seconds after it shuts.
local function useReel(zoneId: number, rolling: boolean): (number, boolean)
	local face, setFace = React.useState(zoneId)
	local detail, setDetail = React.useState(false)
	-- Whether the zone showing now arrived by a roll. A match's first zone is up
	-- before anyone is playing and a remount is not news, and neither deserves a
	-- card explaining itself.
	local spun = React.useRef(false)

	local order = React.useMemo(function()
		local ids = {}
		for _, zone in Zones.List do
			table.insert(ids, zone.id)
		end
		return ids
	end, {})

	React.useEffect(function()
		if not rolling then
			setFace(zoneId)
			if not spun.current then
				return
			end
			spun.current = false
			setDetail(true)

			-- A flag rather than `task.cancel`: the timer usually finishes on its
			-- own, and cancelling a thread that already ran is an error.
			local live = true
			task.delay(DETAIL_SECONDS, function()
				if live then
					setDetail(false)
				end
			end)
			return function()
				live = false
			end
		end

		spun.current = true
		setDetail(false)

		local running = true
		task.spawn(function()
			local step = REEL_FIRST_STEP
			-- Starting somewhere other than the top of the list keeps two rolls in
			-- a row from flicking through the same names in the same order, which
			-- is what would turn the reel back into a loading animation.
			local offset = math.random(0, #order - 1)
			local index = 0
			while running do
				task.wait(step)
				if not running then
					break
				end
				index += 1
				setFace(order[(offset + index) % #order + 1])
				step = math.min(step * REEL_SLOWDOWN, REEL_LAST_STEP)
			end
		end)

		return function()
			running = false
		end
	end, { zoneId, rolling } :: { any })

	return face, detail
end

-- The line under the name. Its own component so the pop-in can hook the mount —
-- it only exists while there is something to say.
local function ZoneDetail(props: { zone: Zones.Zone, width: number })
	local shown, setShown = React.useState(false)
	React.useEffect(function()
		setShown(true)
	end, {})
	local scaleRef = ui.useTweenedScale(if shown then 1 else 0, { tweenInfo = LAND_TWEEN })

	-- Padded against a stroked edge, so the copy clears the panel's border rather
	-- than crowding it. Read at render time so a live theme edit follows.
	local pad = ui.theme.padding + ui.theme.strokeThickness
	local height = DETAIL_LINE_HEIGHT * DETAIL_LINES + pad * 2

	return React.createElement(ui.Slot, {
		size = UDim2.fromOffset(props.width, height),
		layoutOrder = 2,
	}, {
		Pop = React.createElement(ui.Slot, {
			size = UDim2.fromScale(1, 1),
			position = UDim2.fromScale(0.5, 0.5),
			anchorPoint = Vector2.new(0.5, 0.5),
		}, {
			Scale = React.createElement("UIScale", { Scale = 0, ref = scaleRef }),
			Card = React.createElement(ui.Panel, { size = UDim2.fromScale(1, 1) }, {
				Body = React.createElement(ui.Text, {
					-- The same line the classic HUD banners — a zone means one
					-- thing, and it should say it the same way in both modes, so
					-- there is one string on the zone rather than one per surface.
					text = props.zone.warning,
					textSize = DETAIL_TEXT_SIZE,
					weight = Enum.FontWeight.Bold,
					shadow = true,
					wrapped = true,
					xAlignment = Enum.TextXAlignment.Center,
					yAlignment = Enum.TextYAlignment.Center,
					size = UDim2.new(1, -pad * 2, 1, -pad * 2),
					position = UDim2.fromScale(0.5, 0.5),
					anchorPoint = Vector2.new(0.5, 0.5),
				}),
			}),
		}),
	})
end

return function(props: Props)
	local rolling = props.rolling == true
	local face, detail = useReel(props.zoneId, rolling)
	local zone = Zones.get(face)
	local scaleRef = ui.useTweenedScale(if rolling then SPIN_SCALE else 1, { tweenInfo = LAND_TWEEN })

	-- Lit in the zone's own colour while it is spinning and while the news is
	-- still fresh, then handed back to the caller's resting colour: the reel is a
	-- moment, and the line it leaves behind is an ordinary HUD readout again.
	local lit = rolling or detail
	local color = if lit then zone.tint else props.restColor or zone.tint

	local children: { [string]: any } = {
		Name = React.createElement(ui.Slot, {
			size = UDim2.new(1, 0, 0, NAME_HEIGHT),
			layoutOrder = 1,
		}, {
			Pop = React.createElement(ui.Slot, {
				size = UDim2.fromScale(1, 1),
				position = UDim2.fromScale(0.5, 0.5),
				anchorPoint = Vector2.new(0.5, 0.5),
			}, {
				Scale = React.createElement("UIScale", { Scale = 1, ref = scaleRef }),
				Label = React.createElement(ui.Text, {
					text = zone.name,
					textSize = NAME_TEXT_SIZE,
					weight = if lit then Enum.FontWeight.Heavy else Enum.FontWeight.Bold,
					shadow = true,
					color = color,
					xAlignment = Enum.TextXAlignment.Center,
					yAlignment = Enum.TextYAlignment.Center,
					size = UDim2.fromScale(1, 1),
				}),
			}),
		}),
	}

	-- The description always names the zone that *rolled*, never the one the reel
	-- happens to be showing — the two are the same by the time this is up, and
	-- keying it off the roll is what guarantees it.
	if detail then
		children.Detail = React.createElement(ZoneDetail, {
			zone = Zones.get(props.zoneId),
			width = props.width,
		})
	end

	return React.createElement(ui.Stack, {
		size = UDim2.new(1, 0, 0, 0),
		automaticSize = Enum.AutomaticSize.Y,
		gap = 6,
		layoutOrder = props.layoutOrder,
	}, children)
end
