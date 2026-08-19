--!nonstrict
-- UI Labs story for the zone reel.
--
-- `autoRoll` is the one to leave on: it runs the loop the live match runs — spin
-- for the roll window, land on a zone picked at random, hold the description,
-- then do it again — so the whole animation can be watched end to end without a
-- server or a three-minute match.
--
-- Turn it off to drive the reel by hand: `rolling` is the window, `zone` is what
-- it lands on. That pairing is exactly what the HUD passes (`zoneRolling` and
-- `zoneId`), so anything that looks wrong here looks wrong in game.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Features = ReplicatedStorage:WaitForChild("Features")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local UILabs = require(ReplicatedStorage.Packages.UILabs)
local ui = require(ReplicatedStorage.Shared.Boil).ui

local TowerGame = Features:WaitForChild("TowerGame")
local PvpConstants = require(TowerGame:WaitForChild("PvpConstants"))
local ZoneReel = require(TowerGame:WaitForChild("ZoneReel"))
local Zones = require(TowerGame:WaitForChild("Zones"))

-- Built from the list rather than typed out, so a zone added in `Zones.luau`
-- shows up in the dropdown without anyone remembering to add it.
local ZONE_NAMES = {}
local ZONE_IDS = {}
for _, zone in Zones.List do
	table.insert(ZONE_NAMES, zone.name)
	ZONE_IDS[zone.name] = zone.id
end

-- The column the reel sits in on the real HUD. Matching it here is the point:
-- the description card's line count is a function of this width.
local WIDTH = 380
-- What the HUD's other readouts are drawn in, so the reel's resting colour is
-- checked against the thing it actually sits under.
local REST_COLOR = Color3.fromRGB(184, 192, 214)

-- How long the reel rests, landed, before the loop rolls again. Nothing like the
-- match's 35 seconds — this is a story, and the wait is dead time.
local AUTO_REST_SECONDS = 7

local function Demo(props)
	local rolling, setRolling = React.useState(props.rolling)
	local zoneId, setZoneId = React.useState(props.zoneId)

	React.useEffect(function()
		if not props.autoRoll then
			-- Hand control back to the sliders, wherever the loop left the reel.
			setRolling(props.rolling)
			setZoneId(props.zoneId)
			return
		end

		local running = true
		task.spawn(function()
			-- Tracked in the loop rather than read back off state: the effect's
			-- closure captured `zoneId` as it was when the loop started, so rolling
			-- against that would keep avoiding the same one zone forever.
			local current = props.zoneId
			while running do
				setRolling(true)
				task.wait(props.rollSeconds)
				if not running then
					break
				end
				-- A fresh zone every time, which is what makes the landing worth
				-- watching — the reel stopping on the name it stopped on last time
				-- reads as the animation having failed.
				current = Zones.roll(current).id
				setZoneId(current)
				setRolling(false)
				task.wait(AUTO_REST_SECONDS)
			end
		end)

		return function()
			running = false
		end
	end, { props.autoRoll, props.rolling, props.zoneId, props.rollSeconds })

	return React.createElement(ui.Slot, {
		size = UDim2.fromOffset(WIDTH, 200),
		position = UDim2.fromScale(0.5, 0.5),
		anchorPoint = Vector2.new(0.5, 0.5),
	}, {
		Reel = React.createElement(ZoneReel, {
			zoneId = zoneId,
			rolling = rolling,
			width = WIDTH,
			restColor = REST_COLOR,
		}),
	})
end

return {
	summary = "The PVP zone reel: the name flicks through the zone list while the roll window is open, lands on the rolled zone, and says what it does. Leave autoRoll on to watch the whole loop.",
	react = React,
	reactRoblox = ReactRoblox,

	controls = {
		autoRoll = true,
		-- The server's window, so the story spins for as long as a match does.
		rollSeconds = UILabs.Slider(PvpConstants.ZONE_ROLL_SECONDS, 0.5, 6, 0.5),
		zone = UILabs.Choose(ZONE_NAMES),
		rolling = false,
	},

	story = function(props)
		local c = props.controls
		return React.createElement(Demo, {
			autoRoll = c.autoRoll,
			rollSeconds = c.rollSeconds,
			zoneId = ZONE_IDS[c.zone] or Zones.DEFAULT_ID,
			rolling = c.rolling,
		})
	end,
}
