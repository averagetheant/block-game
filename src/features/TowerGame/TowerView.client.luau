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

local BlockLabel = require(ReplicatedStorage.Features.TowerGame.BlockLabel)
local BlockTypes = require(ReplicatedStorage.Features.TowerGame.BlockTypes)
local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)
local ControlsHint = require(ReplicatedStorage.Features.TowerGame.ControlsHint)
local Shapes = require(ReplicatedStorage.Features.TowerGame.Shapes)
local TowerHUD = require(ReplicatedStorage.Features.TowerGame.TowerHUD)
local Zones = require(ReplicatedStorage.Features.TowerGame.Zones)

-- Client-realm siblings (StarterPlayerScripts.Features.*).
local PlayerDataController = require(script.Parent.Parent.PlayerData.PlayerDataController)
local TowerAimController = require(script.Parent.TowerAimController)
local TowerController = require(script.Parent.TowerController)
local TowerFeedbackController = require(script.Parent.TowerFeedbackController)
local TowerZoneController = require(script.Parent.TowerZoneController)

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

	-- The zone banner is a transient: it shows for a few seconds when a special
	-- zone starts, then clears itself.
	local zoneWarning, setZoneWarning = React.useState(nil :: Zones.Zone?)

	React.useEffect(function()
		local alive = true
		local connection = TowerZoneController.ZoneWarned:Connect(function(zone: Zones.Zone)
			setZoneWarning(zone)
			task.delay(Constants.ZONE_WARNING_SECONDS, function()
				if alive then
					setZoneWarning(nil)
				end
			end)
		end)

		return function()
			alive = false
			connection:Disconnect()
		end
	end, {})

	local profile = Boil.useReplica(PlayerDataController, Constants.PROFILE_KEY)

	if state == nil then
		return nil
	end

	local holder = if state.holderUserId ~= 0 then Players:GetPlayerByUserId(state.holderUserId) else nil

	-- The piece's name, composed exactly as the block's own plate composes it, so
	-- the HUD and the world can't disagree about what's in the air. A type that
	-- brings its own model sends shapeId 0 and is named from the type alone.
	local blockType = BlockTypes.get(state.blockTypeId)
	local shape = Shapes.get(state.shapeId)
	local pieceName = BlockLabel.titleFor(
		if blockType then blockType.name else nil,
		if shape then shape.name else nil
	)

	-- Which control list the hint shows. Keyboard wins when several are
	-- available (Studio emulation, a laptop with a touchscreen), because that's
	-- what the player is most likely actually holding.
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local device: ControlsHint.Device = "pc"
	if touchOnly then
		device = "touch"
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		device = "gamepad"
	end

	return React.createElement(TowerHUD, {
		height = state.height,
		maxHeight = state.maxHeight,
		blockCount = state.blockCount,
		phase = state.phase,
		isMyTurn = TowerController.isMyTurn(),
		holderName = if holder then holder.DisplayName else nil,
		holderUserId = state.holderUserId,
		order = state.order,
		shapeName = pieceName,
		nextShapeName = Shapes.nameOf(state.nextShapeId),
		secondsLeft = clocks.turn,
		turnSeconds = state.turnSeconds,
		targetHeight = state.targetHeight,
		zoneBaseHeight = state.zoneBaseHeight,
		stormSecondsLeft = clocks.storm,
		stormSeconds = state.stormSeconds,
		checkpoints = state.checkpoints,
		device = device,
		cash = if profile then profile.Cash or 0 else 0,
		cashAwarded = TowerFeedbackController.CashAwarded,
		zoneWarning = zoneWarning,
		-- Touch-only: keyboard and gamepad go through ContextActionService, so a
		-- PC player would just be looking at buttons they never press.
		showControls = touchOnly,
		-- A tap has no release event, so touch steering moves a fixed distance
		-- rather than starting and stopping a glide.
		onMoveLeft = function()
			TowerAimController.nudge(-1)
		end,
		onMoveRight = function()
			TowerAimController.nudge(1)
		end,
		onRotate = TowerAimController.rotate,
		onDrop = TowerAimController.drop,
	})
end
