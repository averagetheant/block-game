-- Camera presentation for TowerGame: a fixed, level shot of the play plane that
-- rides the tower's altitude and nothing else. No orbit, no follow-the-avatar —
-- the only thing that ever changes is Y and, for one moment per stage, how far
-- back it stands.
--
-- It reads height straight off TowerController's store rather than taking a prop,
-- which is what lets it be deleted (Presentations.camera = false) without any
-- other file noticing. The same goes for the checkpoint pull-back: the server
-- sends no camera cue, it just says PHASE.CHECKPOINT, and this file decides what
-- that looks like.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)

-- Client-realm sibling (StarterPlayerScripts.Features.TowerGame.TowerController).
local TowerController = require(script.Parent.TowerController)

local TowerCameraController = {}

local RENDER_NAME = "TowerGameCamera"

-- The altitude every shot is measured from. The server publishes it as an
-- attribute once the arena exists, which may be after the client boots.
local function waitForBaseTop(): number
	local arena = workspace:WaitForChild(Constants.ARENA_NAME)
	local top = arena:GetAttribute(Constants.BASE_TOP_ATTRIBUTE)
	while top == nil do
		arena:GetAttributeChangedSignal(Constants.BASE_TOP_ATTRIBUTE):Wait()
		top = arena:GetAttribute(Constants.BASE_TOP_ATTRIBUTE)
	end
	return top :: number
end

function TowerCameraController.Start()
	if not Constants.Presentations.camera then
		return
	end

	-- Phone framing is its own shot. A phone held upright has far less vertical
	-- room than a monitor, so the desktop lift put the tower top near the middle
	-- of the screen and everything the player had built ran off the bottom —
	-- which reads as the camera sitting too high. Aim lower, stand further back.
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local aimLift = if touchOnly then Constants.CAMERA_AIM_LIFT_TOUCH else Constants.CAMERA_AIM_LIFT
	local distance = if touchOnly then Constants.CAMERA_DISTANCE_TOUCH else Constants.CAMERA_DISTANCE

	local function shot(aimY: number, from: number): CFrame
		return CFrame.lookAt(Vector3.new(0, aimY, Constants.PLANE_Z + from), Vector3.new(0, aimY, Constants.PLANE_Z))
	end

	-- The checkpoint look: frame the whole leg the players just built, from where
	-- the zone started to the top they reached. The server holds `zoneBaseHeight`
	-- and `height` still for the length of the cutscene precisely so this can be
	-- computed from the ordinary state packet instead of a bespoke camera cue.
	local function wideShot(baseTopY: number, data: TowerController.State): CFrame
		local bottom = baseTopY + math.max(data.zoneBaseHeight, 0)
		local top = baseTopY + math.max(data.height, Constants.CAMERA_MIN_HEIGHT)
		local span = math.max(top - bottom, 1) + Constants.CAMERA_CHECKPOINT_PADDING
		-- Distance that puts `span` studs inside the vertical field of view.
		local needed = span / 2 / math.tan(math.rad(Constants.CAMERA_FOV) / 2)
		return shot(
			(bottom + top) / 2,
			math.clamp(needed, distance * Constants.CAMERA_CHECKPOINT_PULLBACK, Constants.CAMERA_MAX_DISTANCE)
		)
	end

	task.spawn(function()
		local baseTopY = waitForBaseTop()

		local function target(): (CFrame, number)
			local data = TowerController.GetData()
			if data.phase == Constants.PHASE.CHECKPOINT then
				return wideShot(baseTopY, data), Constants.CAMERA_CHECKPOINT_LERP
			end
			local height = math.max(data.height, Constants.CAMERA_MIN_HEIGHT)
			return shot(baseTopY + height + aimLift, distance), Constants.CAMERA_LERP
		end

		local camera = workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = Constants.CAMERA_FOV
		local opening = target()
		camera.CFrame = opening

		RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value, function(deltaTime)
			local current = workspace.CurrentCamera
			-- Respawns and Studio can hand the camera back to the default script;
			-- reclaiming it each frame is cheaper than watching for that.
			if current.CameraType ~= Enum.CameraType.Scriptable then
				current.CameraType = Enum.CameraType.Scriptable
			end
			-- Framerate-independent exponential follow: the tower can grow by a
			-- whole block between frames and this stays smooth either way. The
			-- checkpoint pull-back returns a slower rate, so the move eases out
			-- instead of tracking.
			local goal, rate = target()
			local alpha = 1 - math.exp(-rate * deltaTime)
			current.CFrame = current.CFrame:Lerp(goal, alpha)
		end)
	end)
end

return TowerCameraController
