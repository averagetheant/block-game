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
local PvpConstants = require(ReplicatedStorage.Features.TowerGame.PvpConstants)
local Shapes = require(ReplicatedStorage.Features.TowerGame.Shapes)
local TowerHUD = require(ReplicatedStorage.Features.TowerGame.TowerHUD)
local Zones = require(ReplicatedStorage.Features.TowerGame.Zones)

-- Client-realm siblings (StarterPlayerScripts.Features.*).
local PlayerDataController = require(script.Parent.Parent.PlayerData.PlayerDataController)
local PvpController = require(script.Parent.PvpController)
local TowerAimController = require(script.Parent.TowerAimController)
local TowerCameraController = require(script.Parent.TowerCameraController)
local TowerController = require(script.Parent.TowerController)
local TowerFeedbackController = require(script.Parent.TowerFeedbackController)
local TowerZoneController = require(script.Parent.TowerZoneController)
-- Prompting a purchase is a client call. The HUD only gets a callback — it
-- never learns there's a product id behind the button.
local StoreController = require(script.Parent.Parent.Store.StoreController)

-- What the machine has, used until the player touches something. Keyboard wins
-- when several are available (Studio emulation, a laptop with a touchscreen),
-- because that's what they're most likely actually holding.
local function initialDevice(): ControlsHint.Device
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "touch"
	end
	if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "gamepad"
	end
	return "pc"
end

-- The device the last real input came from, or nil for inputs that say nothing
-- about what's in the player's hands. `Focus` and `TextInput` fire from window
-- focus and the chat bar; treating either as "they switched to a keyboard"
-- would flip a console player's hint for no reason.
local function deviceOf(inputType: Enum.UserInputType): ControlsHint.Device?
	if inputType == Enum.UserInputType.Touch then
		return "touch"
	end
	if inputType == Enum.UserInputType.Keyboard or string.match(inputType.Name, "^Mouse") then
		return "pc"
	end
	if string.match(inputType.Name, "^Gamepad") then
		return "gamepad"
	end
	return nil
end

-- Follows the input the player is actually using. Capability alone isn't enough:
-- a PC with a controller plugged in has KeyboardEnabled *and* GamepadEnabled, so
-- a purely capability-based answer would show keyboard hints to someone holding
-- a pad.
local function useDevice(): ControlsHint.Device
	local device, setDevice = React.useState(initialDevice)

	React.useEffect(function()
		local connection = UserInputService.LastInputTypeChanged:Connect(function(inputType)
			local nextDevice = deviceOf(inputType)
			if nextDevice == nil then
				return
			end
			-- Setting the value it already holds makes React bail out of the
			-- update, so the common case (every mouse move on a PC) is free.
			setDevice(nextDevice)
		end)
		return function()
			connection:Disconnect()
		end
	end, {})

	return device
end

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

	-- Mirrors TowerCameraController's toggle so the button can colour itself.
	-- Seeded from the controller rather than assumed false, so a remount doesn't
	-- show the button in the wrong state.
	local overview, setOverview = React.useState(TowerCameraController.isOverview)

	local profile = Boil.useReplica(PlayerDataController, Constants.PROFILE_KEY)
	-- Subscribed to, not just read: this HUD has to come down the frame a match
	-- starts and go back up the frame it ends, and neither is a change to the
	-- classic state packet — which the server stops sending for the duration.
	local pvp = Boil.useReplica(PvpController)

	-- Which control list the hint shows, and whether the touch buttons render.
	-- `useDevice` starts from what the machine *has* and then follows what the
	-- player actually *uses*, so plugging in a controller on a PC switches the
	-- hint to the stick bindings the moment it's touched.
	--
	-- Called up here with the rest of the hooks and *above* the early returns
	-- below, not down beside the render that reads it. React identifies a hook by
	-- call order, so a hook that only runs on the renders that get past a guard is
	-- a different hook count each time — which is exactly what "Rendered fewer
	-- hooks than expected" means. It fired every time a PVP round started (the
	-- guard below trips, the render is one `useState`/`useEffect` shorter, React
	-- throws) and took the whole UI root down with it. Every hook in this file
	-- runs unconditionally; the guards start after the last one.
	local device = useDevice()

	if state == nil then
		return nil
	end

	-- A PVP round owns the board, and everything this HUD draws — the turn strip,
	-- the storm clock, the target — is about a game that isn't being played. The
	-- PVP HUD is its own root presentation (see PvpPresentation) and takes over.
	if pvp ~= nil and pvp.phase ~= PvpConstants.PHASE.OFF then
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

	local touchOnly = device == "touch"

	return React.createElement(TowerHUD, {
		height = state.height,
		blockCount = state.blockCount,
		phase = state.phase,
		isMyTurn = TowerController.isMyTurn(),
		holderName = if holder then holder.DisplayName else nil,
		holderUserId = state.holderUserId,
		order = state.order,
		repeatUserId = state.repeatUserId,
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
		-- The stick reports a continuous deflection, which goes straight into the
		-- same analog steer the gamepad uses — a drag holds the piece moving for
		-- as long as the thumb is down, and reports 0 when it lifts.
		onSteer = TowerAimController.setSteer,
		onRotate = TowerAimController.rotate,
		onDrop = TowerAimController.drop,

		-- The camera pull-back. State lives in the camera controller, not here:
		-- it's the thing that has to arbitrate the toggle against the checkpoint
		-- and round-break shots, so it owns the answer and this only mirrors it.
		overview = overview,
		onToggleCamera = function()
			setOverview(TowerCameraController.toggleOverview())
		end,

		-- Gated on the same flag as the rail's Nuke and Skip: a build with the
		-- actions presentation off shouldn't offer this one either. nil here is
		-- what makes the HUD leave the button out entirely.
		onExtendStorm = if Constants.Presentations.actions
			then function()
				StoreController.promptProduct(Constants.PRODUCTS.EXTEND_STORM)
			end
			else nil,
	})
end
