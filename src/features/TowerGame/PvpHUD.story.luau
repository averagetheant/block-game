--!nonstrict
-- UI Labs story for the PVP HUD. Every prop the live game feeds it is a slider or
-- a dropdown here — including the phase, so the countdown and the final standings
-- can be looked at without waiting out a three-minute match.
--
-- `playerCount` is the one worth playing with: it fills the height rail down the
-- right edge as well as the final standings, so this is how you check a full
-- lobby's faces stay apart on the rail and a one-player match doesn't leave a
-- lonely panel. `HeightRail.story` drives the rail on its own, with the scale and
-- the pile-up on sliders of their own.
--
-- Set `phase` to `results` and the rail and the top bar go away, leaving the
-- final standings alone in the middle — that's the game's behaviour, not a story
-- shortcut.
--
-- `showControls` is forced on by default because the touch control row is the
-- part worth eyeballing in-editor; in game it only renders on touch devices.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Features = ReplicatedStorage:WaitForChild("Features")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local UILabs = require(ReplicatedStorage.Packages.UILabs)

local TowerGame = Features:WaitForChild("TowerGame")
local PvpConstants = require(TowerGame:WaitForChild("PvpConstants"))
local PvpHUD = require(TowerGame:WaitForChild("PvpHUD"))
local Zones = require(TowerGame:WaitForChild("Zones"))

local PHASE_NAMES = { "playing", "countdown", "results" }

-- The zone dropdown, built from the list rather than typed out, so a zone added
-- in `Zones.luau` shows up here without anyone remembering to add it.
local ZONE_NAMES = {}
local ZONE_IDS = {}
for _, zone in Zones.List do
	table.insert(ZONE_NAMES, zone.name)
	ZONE_IDS[zone.name] = zone.id
end

-- Real user ids so `Players:GetPlayerByUserId` misses cleanly and the fallback
-- name is exercised — the story has no other players in the place, which is
-- exactly the "left mid-match" case the view has to survive. One of these seats
-- is overwritten with the local player's own id below; the rest stay strangers.
local ROSTER = {
	{ userId = 1, name = "BlockFan42" },
	{ userId = 2, name = "TowerGoblin" },
	{ userId = 3, name = "Stackmaster" },
	{ userId = 4, name = "Nootnoot" },
	{ userId = 5, name = "Bricklayer" },
	{ userId = 6, name = "Wobbles" },
}

return {
	summary = "PVP HUD driven by controls. Phase picks between the countdown, the live round and the final standings; the clocks are sliders. One roster seat is handed your own user id, so the rail lights the face it would light in game. No server needed.",
	react = React,
	reactRoblox = ReactRoblox,

	controls = {
		phase = UILabs.Choose(PHASE_NAMES),
		secondsLeft = UILabs.Slider(96, 0, PvpConstants.MATCH_SECONDS, 1),
		playerCount = UILabs.Slider(4, 1, PvpConstants.MAX_LANES, 1),
		-- Where the local player sits in the standings. Drives which colour the
		-- place readout takes, and — through `ROSTER` — which face on the rail is
		-- lit and carries the reading in studs.
		myRank = UILabs.Slider(2, 1, PvpConstants.MAX_LANES, 1),
		-- A spectator, or a player who arrived after every seat was taken. The
		-- place readout becomes "Watching" and the rail lights nobody.
		playing = true,
		holding = true,
		pieceSecondsLeft = UILabs.Slider(12, 0, PvpConstants.PIECE_SECONDS, 1),
		pieceName = UILabs.Choose({ "T-Shape", "I-Shape", "Bomb T-Shape", "Burning L-Shape", "Noob" }),
		zone = UILabs.Choose(ZONE_NAMES),
		-- The roll window. Flip it on and off to watch the reel spin through the
		-- names and land on whichever zone is picked above, description and all —
		-- the live game flips it from the server's `zoneAt` stamp.
		zoneRolling = false,
		device = UILabs.Choose({ "pc", "touch", "gamepad" }),
		showControls = true,
		showHint = true,
		-- The counter is shared with the classic HUD; it's here so the bottom-right
		-- corner can be checked as a pair with the camera toggle stacked above it.
		-- Only colours the camera button; the real state lives in the camera
		-- controller, which the story doesn't run.
		overview = false,
	},

	story = function(props)
		local c = props.controls

		local phase = PvpConstants.PHASE.PLAYING
		if c.phase == "countdown" then
			phase = PvpConstants.PHASE.COUNTDOWN
		elseif c.phase == "results" then
			phase = PvpConstants.PHASE.RESULTS
		end

		-- Heights that descend, so the board is already in standings order and the
		-- medal colours land on the rows they're meant to.
		local standings = {}
		for index = 1, math.min(c.playerCount, #ROSTER) do
			local entry = ROSTER[index]
			table.insert(standings, {
				userId = entry.userId,
				name = entry.name,
				height = math.max(0, 120 - (index - 1) * 17.5),
			})
		end

		-- One roster seat is handed the *real* local user id, because both surfaces
		-- that mark "you" — the lit face on the rail and the gold edge on the final
		-- standings — find it by matching `Players.LocalPlayer.UserId`. Without
		-- this the story draws a HUD belonging to nobody, and the one thing the
		-- rail is for (find yourself, then everyone else relative to you) can't be
		-- looked at in-editor at all. `myRank` picks which seat.
		local mine = if c.playing then standings[math.clamp(c.myRank, 1, #standings)] else nil
		if mine then
			mine.userId = Players.LocalPlayer.UserId
		end

		return React.createElement(PvpHUD, {
			phase = phase,
			secondsLeft = if phase == PvpConstants.PHASE.COUNTDOWN
				then math.min(c.secondsLeft, PvpConstants.COUNTDOWN_SECONDS)
				else c.secondsLeft,
			matchSeconds = PvpConstants.MATCH_SECONDS,
			zoneId = ZONE_IDS[c.zone] or 1,
			zoneRolling = c.zoneRolling,
			standings = standings,
			myRank = if c.playing then c.myRank else 0,
			holding = c.holding,
			pieceName = c.pieceName,
			pieceSecondsLeft = c.pieceSecondsLeft,
			device = c.device,
			showControls = c.showControls,
			showHint = c.showHint,
			overview = c.overview,
			onToggleCamera = function()
				print("[PvpHUD.story] toggle camera")
			end,
			onSteer = function(value)
				print(`[PvpHUD.story] steer {string.format("%.2f", value)}`)
			end,
			onRotate = function()
				print("[PvpHUD.story] rotate")
			end,
			onDrop = function()
				print("[PvpHUD.story] drop")
			end,
		})
	end,
}
