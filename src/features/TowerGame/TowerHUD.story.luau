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

local TowerGame = Features:WaitForChild("TowerGame")
local Constants = require(TowerGame:WaitForChild("Constants"))
local TowerHUD = require(TowerGame:WaitForChild("TowerHUD"))

local PHASE_NAMES = { "aiming (yours)", "aiming (someone else)", "settling", "idle" }

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
		shapeName = UILabs.Choose({ "I", "O", "T", "S", "Z", "J", "L" }),
		showControls = true,
	},

	story = function(props)
		local c = props.controls
		local selected = c.phase

		local phase = Constants.PHASE.AIMING
		if selected == "settling" then
			phase = Constants.PHASE.SETTLING
		elseif selected == "idle" then
			phase = Constants.PHASE.IDLE
		end

		return React.createElement(TowerHUD, {
			height = c.height,
			maxHeight = c.maxHeight,
			blockCount = c.blockCount,
			phase = phase,
			isMyTurn = selected == "aiming (yours)",
			holderName = "BlockFan42",
			shapeName = c.shapeName,
			nextShapeName = "T",
			secondsLeft = c.secondsLeft,
			turnSeconds = Constants.TURN_SECONDS,
			showControls = c.showControls,
			onMoveLeft = function()
				print("[TowerHUD.story] move left")
			end,
			onMoveRight = function()
				print("[TowerHUD.story] move right")
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
