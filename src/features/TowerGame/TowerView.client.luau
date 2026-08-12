-- Stateful container for the TowerGame HUD. Subscribes to the controller's store
-- with the shared useReplica hook, turns the server-time deadline into a ticking
-- countdown, and hands the result to the dumb HUD.
--
-- The countdown is the only state this file owns: the server broadcasts a
-- deadline once per turn, not a per-second tick, so somebody has to run the clock
-- locally and it may as well be the component that displays it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local React = require(ReplicatedStorage.Packages.React)
local Boil = require(ReplicatedStorage.Shared.Boil)

local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)
local Shapes = require(ReplicatedStorage.Features.TowerGame.Shapes)
local TowerHUD = require(ReplicatedStorage.Features.TowerGame.TowerHUD)

-- Client-realm sibling (StarterPlayerScripts.Features.TowerGame.TowerController).
local TowerController = require(script.Parent.TowerController)

return function()
	local state = Boil.useReplica(TowerController)
	local clocks, setClocks = React.useState({ turn = 0, storm = 0 })

	React.useEffect(function()
		local connection = RunService.Heartbeat:Connect(function()
			local turn = TowerController.secondsLeft()
			local storm = TowerController.stormSecondsLeft()
			-- Only re-render when a *displayed* second changes; returning the
			-- previous table makes React bail out of the update entirely.
			setClocks(function(previous)
				if math.ceil(previous.turn) == math.ceil(turn) and math.ceil(previous.storm) == math.ceil(storm) then
					return previous
				end
				return { turn = turn, storm = storm }
			end)
		end)

		return function()
			connection:Disconnect()
		end
	end, {})

	if state == nil then
		return nil
	end

	local holder = if state.holderUserId ~= 0 then Players:GetPlayerByUserId(state.holderUserId) else nil

	return React.createElement(TowerHUD, {
		height = state.height,
		maxHeight = state.maxHeight,
		blockCount = state.blockCount,
		phase = state.phase,
		isMyTurn = TowerController.isMyTurn(),
		holderName = if holder then holder.DisplayName else nil,
		shapeName = Shapes.nameOf(state.shapeId),
		nextShapeName = Shapes.nameOf(state.nextShapeId),
		secondsLeft = clocks.turn,
		turnSeconds = Constants.TURN_SECONDS,
		targetHeight = state.targetHeight,
		stormSecondsLeft = clocks.storm,
		stormSeconds = Constants.STORM_SECONDS,
		checkpoints = state.checkpoints,
		-- Touch-only: keyboard and gamepad go through ContextActionService, so a
		-- PC player would just be looking at buttons they never press.
		showControls = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled,
		-- A tap has no release event, so touch steering is a timed pulse rather
		-- than the press/release the other devices send.
		onMoveLeft = function()
			TowerController.nudge(-1)
		end,
		onMoveRight = function()
			TowerController.nudge(1)
		end,
		onRotate = function()
			TowerController.rotate(true)
		end,
		onDrop = TowerController.drop,
	})
end
