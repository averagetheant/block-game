-- Stateful container for the PVP HUD. Subscribes to PvpController's store with
-- the shared useReplica hook, runs the two clocks locally, resolves the names on
-- the standings, and hands the result to the dumb HUD.
--
-- Renders **nothing at all** when no match is running, which is what makes the
-- mode's whole UI a single mount point: the classic HUD does the same in reverse
-- (see `TowerView`), so exactly one of the two is ever on screen and neither has
-- to know what the other draws.
--
-- The clocks are the only state this file owns. The server broadcasts deadlines,
-- not ticks, so somebody has to count locally and it may as well be the component
-- that displays the number.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local React = require(ReplicatedStorage.Packages.React)
local Boil = require(ReplicatedStorage.Shared.Boil)

local BlockLabel = require(ReplicatedStorage.Features.TowerGame.BlockLabel)
local BlockTypes = require(ReplicatedStorage.Features.TowerGame.BlockTypes)
local ControlsHint = require(ReplicatedStorage.Features.TowerGame.ControlsHint)
local PvpConstants = require(ReplicatedStorage.Features.TowerGame.PvpConstants)
local PvpHUD = require(ReplicatedStorage.Features.TowerGame.PvpHUD)
local Shapes = require(ReplicatedStorage.Features.TowerGame.Shapes)

-- Client-realm siblings (StarterPlayerScripts.Features.TowerGame.*).
local PvpController = require(script.Parent.PvpController)
local TowerAimController = require(script.Parent.TowerAimController)
local TowerCameraController = require(script.Parent.TowerCameraController)
local TowerController = require(script.Parent.TowerController)

-- Same rule as the classic view's: start from what the machine has, then follow
-- what the player actually uses. Kept as its own small copy rather than exported
-- from TowerView, because that file is a component and this one only wants the
-- hook — see the note there for why capability alone is the wrong answer.
local function initialDevice(): ControlsHint.Device
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "touch"
	end
	if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "gamepad"
	end
	return "pc"
end

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

local function useDevice(): ControlsHint.Device
	local device, setDevice = React.useState(initialDevice)

	React.useEffect(function()
		local connection = UserInputService.LastInputTypeChanged:Connect(function(inputType)
			local nextDevice = deviceOf(inputType)
			if nextDevice ~= nil then
				setDevice(nextDevice)
			end
		end)
		return function()
			connection:Disconnect()
		end
	end, {})

	return device
end

-- A display name for a user id.
--
-- The player object when they're still here, which covers everybody during a
-- match. A leaver's lane is retired the moment they go, so the only way a name
-- can be missing is a lane whose player left between the packet being sent and
-- it being read — one frame, and "Player" for that frame beats yielding the
-- whole HUD on `GetNameFromUserIdAsync`.
local function nameOf(userId: number): string
	local player = Players:GetPlayerByUserId(userId)
	return if player then player.DisplayName else "Player"
end

return function()
	local state = Boil.useReplica(PvpController)
	-- One number, because only one clock runs per phase (see `endsAt` in
	-- PvpPackets): the countdown, then the match, then the results.
	local phaseClock, setPhaseClock = React.useState(0)
	local pieceClock, setPieceClock = React.useState(0)
	-- Whether the zone on the packet is still inside its roll window. Counted here
	-- with the clocks for the same reason they are: the server broadcasts the
	-- moment it lands, not a tick, so somebody local has to notice it passing.
	local zoneRolling, setZoneRolling = React.useState(false)

	React.useEffect(function()
		local connection = RunService.Heartbeat:Connect(function()
			local phaseLeft = PvpController.secondsLeft()
			local pieceLeft = TowerController.pieceSecondsLeft()
			-- Only re-render when a *displayed* second changes; returning the same
			-- value makes React bail out of the update entirely.
			setPhaseClock(function(previous)
				return if math.ceil(previous) == math.ceil(phaseLeft) then previous else phaseLeft
			end)
			setPieceClock(function(previous)
				return if math.ceil(previous) == math.ceil(pieceLeft) then previous else pieceLeft
			end)
			-- Unchanged almost every frame, and React bails out of an update to the
			-- same value — so this costs a comparison, not a render.
			setZoneRolling(PvpController.zoneRolling())
		end)

		return function()
			connection:Disconnect()
		end
	end, {})

	-- Mirrors TowerCameraController's toggle so the button can colour itself.
	-- Seeded from the controller rather than assumed false, so a remount doesn't
	-- show the button in the wrong state.
	local overview, setOverview = React.useState(TowerCameraController.isOverview)

	local device = useDevice()

	if state == nil or state.phase == PvpConstants.PHASE.OFF then
		return nil
	end

	local standings = {}
	for _, lane in PvpController.standings() do
		table.insert(standings, {
			userId = lane.userId,
			name = nameOf(lane.userId),
			height = lane.height,
		})
	end

	local mine = PvpController.myLane()

	-- The piece's name, composed exactly as the block's own plate composes it, so
	-- the HUD and the world can't disagree about what's in the air.
	local blockType = if mine then BlockTypes.get(mine.blockTypeId) else nil
	local shape = if mine then Shapes.get(mine.shapeId) else nil
	local pieceName = BlockLabel.titleFor(
		if blockType then blockType.name else nil,
		if shape then shape.name else nil
	)

	return React.createElement(PvpHUD, {
		phase = state.phase,
		secondsLeft = phaseClock,
		matchSeconds = state.matchSeconds,
		zoneId = state.zoneId,
		zoneRolling = zoneRolling,
		standings = standings,
		-- 0 while spectating. The HUD reads this player's height off their row in
		-- `standings` rather than taking it as a prop of its own, so there is one
		-- number and one place it comes from.
		myRank = PvpController.myRank(),
		holding = mine ~= nil and mine.holding,
		pieceName = pieceName,
		pieceSecondsLeft = pieceClock,
		device = device,
		-- Touch-only: keyboard and gamepad go through ContextActionService, so a
		-- PC player would just be looking at buttons they never press.
		showControls = device == "touch",

		-- The same four intents the classic HUD calls. Aiming is one
		-- implementation across both modes — see `TowerController.isAiming`.
		onSteer = TowerAimController.setSteer,
		onRotate = TowerAimController.rotate,
		onDrop = TowerAimController.drop,

		overview = overview,
		onToggleCamera = function()
			setOverview(TowerCameraController.toggleOverview())
		end,
	})
end
