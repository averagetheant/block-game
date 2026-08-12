-- Mouse presentation for TowerGame (PC): the piece follows the pointer and drops
-- on click. An *alternative* to the keyboard, not a replacement — both stay live,
-- and they don't fight because this only speaks while the mouse is actually
-- moving, and the server drops any held steer direction when an aim arrives.
--
-- The mouse is a screen position and the piece lives on a world plane, so every
-- frame that matters we cast the pointer into the world and solve for where it
-- crosses Z = PLANE_Z. That's the X the piece wants.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)

-- Client-realm sibling (StarterPlayerScripts.Features.TowerGame.TowerController).
local TowerController = require(script.Parent.TowerController)

local TowerPointerController = {}

-- Screen movement (in pixels) that counts as "the player moved the mouse".
local MOVE_THRESHOLD = 1

-- Where the pointer crosses the play plane, or nil if it never does (the camera
-- is level with the plane, or the plane is behind the viewer).
local function pointerPlaneX(mouse: Mouse): number?
	local camera = workspace.CurrentCamera
	if camera == nil then
		return nil
	end

	local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)
	local directionZ = ray.Direction.Z
	if math.abs(directionZ) < 1e-4 then
		return nil
	end

	local distance = (Constants.PLANE_Z - ray.Origin.Z) / directionZ
	if distance <= 0 then
		return nil
	end
	return ray.Origin.X + ray.Direction.X * distance
end

function TowerPointerController.Start()
	if not Constants.Presentations.pointer then
		return
	end
	-- Touch devices drive the HUD buttons instead; a touch "mouse" would make the
	-- piece jump to wherever the last tap landed.
	if not UserInputService.MouseEnabled or UserInputService.TouchEnabled then
		return
	end

	local mouse = Players.LocalPlayer:GetMouse()
	local lastScreen: Vector2? = nil
	local lastSentAt = 0
	local lastX: number? = nil

	RunService.RenderStepped:Connect(function()
		if not TowerController.isMyTurn() then
			-- Re-baseline while we wait, so the piece doesn't snap to a stale
			-- pointer position the instant the turn arrives.
			lastScreen = nil
			lastX = nil
			return
		end

		local screen = Vector2.new(mouse.X, mouse.Y)
		if lastScreen == nil then
			-- First frame of our turn: note where the pointer is, but don't treat
			-- it as movement. A keyboard player who never touches the mouse is
			-- never overridden by it.
			lastScreen = screen
			return
		end
		if (screen - lastScreen).Magnitude < MOVE_THRESHOLD then
			return
		end
		lastScreen = screen

		local now = os.clock()
		if now - lastSentAt < Constants.AIM_INTERVAL then
			return
		end

		local x = pointerPlaneX(mouse)
		if x == nil then
			return
		end
		if lastX ~= nil and math.abs(x - lastX) < Constants.AIM_EPSILON then
			return
		end

		lastSentAt = now
		lastX = x
		TowerController.aim(x)
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		-- gameProcessed is what keeps a click on the HUD's own buttons from also
		-- dropping the piece.
		if gameProcessed then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		TowerController.drop()
	end)
end

return TowerPointerController
