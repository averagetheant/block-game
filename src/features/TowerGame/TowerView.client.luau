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
	local secondsLeft, setSecondsLeft = React.useState(0)

	React.useEffect(function()
		local connection = RunService.Heartbeat:Connect(function()
			local remaining = TowerController.secondsLeft()
			-- Only re-render when the *displayed* second changes; returning the
			-- previous value makes React bail out of the update entirely.
			setSecondsLeft(function(previous: number)
				if math.ceil(previous) == math.ceil(remaining) then
					return previous
				end
				return remaining
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
		secondsLeft = secondsLeft,
		turnSeconds = Constants.TURN_SECONDS,
		-- Touch-only: keyboard and gamepad go through ContextActionService, so a
		-- PC player would just be looking at buttons they never press.
		showControls = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled,
		onMoveLeft = TowerController.moveLeft,
		onMoveRight = TowerController.moveRight,
		onRotate = function()
			TowerController.rotate(true)
		end,
		onDrop = TowerController.drop,
	})
end
