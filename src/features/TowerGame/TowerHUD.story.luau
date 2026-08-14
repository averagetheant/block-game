--!nonstrict
-- UI Labs story for the TowerGame HUD. Every prop the live game feeds it is a
-- slider or a dropdown here, including the turn clock — so you can park the timer
-- at 3s and check the urgent (red) state without waiting out a real turn.
--
-- `showControls` is forced on by default because the touch control row is the
-- part worth eyeballing in-editor; in game it only renders on touch devices.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Features = ReplicatedStorage:WaitForChild("Features")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local UILabs = require(ReplicatedStorage.Packages.UILabs)

local Signal = require(ReplicatedStorage.Packages.Signal)

local TowerGame = Features:WaitForChild("TowerGame")
local Constants = require(TowerGame:WaitForChild("Constants"))
local TowerHUD = require(TowerGame:WaitForChild("TowerHUD"))
local Zones = require(TowerGame:WaitForChild("Zones"))

local PHASE_NAMES =
	{ "aiming (yours)", "aiming (someone else)", "settling", "checkpoint", "game over", "idle" }

-- Stands in for TowerFeedbackController.CashAwarded. The story fires it on a
-- timer so the bill burst plays on a loop while you tune it.
local fakeAward = Signal.new()

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
		maxHeight = UILabs.Slider(48, 0, 300, 0.5),
		blockCount = UILabs.Slider(11, 0, 200, 1),
		secondsLeft = UILabs.Slider(13, 0, Constants.TURN_SECONDS, 1),
		targetHeight = UILabs.Slider(120, 0, 600, 1),
		zoneBaseHeight = UILabs.Slider(0, 0, 600, 1),
		stormSecondsLeft = UILabs.Slider(148, 0, Constants.STORM_SECONDS, 1),
		checkpoints = UILabs.Slider(1, 0, 20, 1),
		playerCount = UILabs.Slider(4, 1, 8, 1),
		-- Tags the current player's chip "2x" — what a Double Turn owner's
		-- headshot looks like while their second piece is still coming.
		doubleTurn = false,
		cash = UILabs.Slider(1250, 0, 100000, 10),
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

		-- Fire a payout every couple of seconds so the burst is always visible
		-- while the story is open.
		React.useEffect(function()
			local running = true
			task.spawn(function()
				while running do
					task.wait(2)
					fakeAward:Fire(50)
				end
			end)
			return function()
				running = false
			end
		end, {})

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
			maxHeight = c.maxHeight,
			blockCount = c.blockCount,
			phase = phase,
			isMyTurn = selected == "aiming (yours)",
			holderName = "BlockFan42",
			holderUserId = if phase == Constants.PHASE.AIMING then order[1] or 0 else 0,
			order = order,
			-- The Double Turn tag on the current player's chip.
			repeatUserId = if c.doubleTurn then order[1] or 0 else 0,
			device = c.device,
			cash = c.cash,
			-- A stand-in for the controller's signal: the story fires it from the
			-- button below so the bill burst can be watched without a server.
			cashAwarded = fakeAward,
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
		})
	end,
}
