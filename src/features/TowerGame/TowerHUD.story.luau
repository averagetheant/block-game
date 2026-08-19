--!nonstrict
-- UI Labs story for the TowerGame HUD. Every prop the live game feeds it is a
-- slider or a dropdown here, including the turn clock — so you can park the timer
-- at 3s and check the urgent (red) state without waiting out a real turn.
--
-- The touch row also needs a turn this player can act in — it's hidden on anyone
-- else's — so it shows on the "aiming (yours)" phase and nowhere else.
--
-- `showControls` is forced on by default because the touch control row is the
-- part worth eyeballing in-editor; in game it only renders on touch devices.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Features = ReplicatedStorage:WaitForChild("Features")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local UILabs = require(ReplicatedStorage.Packages.UILabs)


local TowerGame = Features:WaitForChild("TowerGame")
local Constants = require(TowerGame:WaitForChild("Constants"))
local SkinPacks = require(TowerGame:WaitForChild("SkinPacks"))
local TowerHUD = require(TowerGame:WaitForChild("TowerHUD"))
local Zones = require(TowerGame:WaitForChild("Zones"))

-- Resolved the same way TowerView resolves it, off the pack the server grants.
local questPack = SkinPacks.get(Constants.FIRST_CHECKPOINT_PACK)
local questRewardName = if questPack then questPack.name else "A rare skin"

local PHASE_NAMES =
	{ "aiming (yours)", "aiming (someone else)", "settling", "checkpoint", "game over", "idle" }

local function zoneByName(name: string): Zones.Zone?
	if name == "none" then
		return nil
	end
	for _, zone in Zones.List do
		if zone.name == name then
			return zone
		end
	end
	return nil
end

return {
	summary = "TowerGame HUD driven by controls. Phase picks the status line; the timer slider drives the countdown bar (red under 5s). No server needed.",
	react = React,
	reactRoblox = ReactRoblox,

	controls = {
		phase = UILabs.Choose(PHASE_NAMES),
		height = UILabs.Slider(24.5, 0, 300, 0.5),
		blockCount = UILabs.Slider(11, 0, 200, 1),
		secondsLeft = UILabs.Slider(13, 0, Constants.TURN_SECONDS, 1),
		targetHeight = UILabs.Slider(120, 0, 600, 1),
		zoneBaseHeight = UILabs.Slider(0, 0, 600, 1),
		stormSecondsLeft = UILabs.Slider(148, 0, Constants.STORM_SECONDS, 1),
		checkpoints = UILabs.Slider(1, 0, 20, 1),
		-- On by default so the quest line is what you see first; in game it's off
		-- for anyone who has already cleared a checkpoint.
		showCheckpointQuest = true,
		-- The payoff side of the line — what a new player sees for a few seconds
		-- once the grant lands. Once ever in game, so this is where to look at it.
		questClaimed = false,
		playerCount = UILabs.Slider(4, 1, 8, 1),
		-- Tags the current player's chip "2x" — what a Double Turn owner's
		-- headshot looks like while their second piece is still coming.
		doubleTurn = false,
		-- The composed piece name, exactly as TowerView builds it from the shape
			-- and the block type.
			shapeName = UILabs.Choose({ "T-Shape", "I-Shape", "Bomb T-Shape", "Burning L-Shape", "Noob" }),
		device = UILabs.Choose({ "pc", "touch", "gamepad" }),
		zoneWarning = UILabs.Choose({ "none", "Retro Zone", "Snowy Zone", "Stormy Zone", "Space Zone" }),
		showControls = true,
		-- Only colours the camera button; the real state lives in the camera
		-- controller, which the story doesn't run.
		overview = false,
	},

	story = function(props)
		local c = props.controls
		local selected = c.phase
		local warningZone = zoneByName(c.zoneWarning)

		local phase = Constants.PHASE.AIMING
		if selected == "settling" then
			phase = Constants.PHASE.SETTLING
		elseif selected == "checkpoint" then
			phase = Constants.PHASE.CHECKPOINT
		elseif selected == "game over" then
			phase = Constants.PHASE.GAMEOVER
		elseif selected == "idle" then
			phase = Constants.PHASE.IDLE
		end

		-- Real user ids so the strip pulls real headshots. Any ids would do; these
		-- are the first few accounts ever created, which are guaranteed to exist.
		local roster = { 1, 2, 3, 4, 5, 6, 7, 8 }
		local order = {}
		for index = 1, math.min(c.playerCount, #roster) do
			table.insert(order, roster[index])
		end

		return React.createElement(TowerHUD, {
			height = c.height,
			blockCount = c.blockCount,
			phase = phase,
			isMyTurn = selected == "aiming (yours)",
			holderName = "BlockFan42",
			holderUserId = if phase == Constants.PHASE.AIMING then order[1] or 0 else 0,
			order = order,
			-- The Double Turn tag on the current player's chip.
			repeatUserId = if c.doubleTurn then order[1] or 0 else 0,
			device = c.device,
			zoneWarning = warningZone,
			shapeName = c.shapeName,
			nextShapeName = "T",
			secondsLeft = c.secondsLeft,
			turnSeconds = Constants.TURN_SECONDS,
			targetHeight = c.targetHeight,
			zoneBaseHeight = c.zoneBaseHeight,
			stormSecondsLeft = c.stormSecondsLeft,
			stormSeconds = Constants.STORM_SECONDS,
			checkpoints = c.checkpoints,
			showCheckpointQuest = c.showCheckpointQuest,
			questClaimed = c.questClaimed,
			questRewardName = questRewardName,
			showControls = c.showControls,
			onSteer = function(value)
				print(`[TowerHUD.story] steer {string.format("%.2f", value)}`)
			end,
			overview = c.overview,
			onToggleCamera = function()
				print("[TowerHUD.story] toggle camera")
			end,
			onRotate = function()
				print("[TowerHUD.story] rotate")
			end,
			onDrop = function()
				print("[TowerHUD.story] drop")
			end,
			-- Present so the button renders here; in game this is nil whenever
			-- the actions presentation is off.
			onExtendStorm = function()
				print("[TowerHUD.story] extend storm")
			end,
		})
	end,
}
