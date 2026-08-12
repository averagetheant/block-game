-- Camera presentation for TowerGame: a fixed, level shot of the play plane that
-- rides the tower's altitude and nothing else. No orbit, no follow-the-avatar —
-- the only thing that ever changes is Y.
--
-- It reads height straight off TowerController's store rather than taking a prop,
-- which is what lets it be deleted (Presentations.camera = false) without any
-- other file noticing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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

	task.spawn(function()
		local baseTopY = waitForBaseTop()

		local function target(): CFrame
			local height = math.max(TowerController.GetData().height, Constants.CAMERA_MIN_HEIGHT)
			local aimY = baseTopY + height + Constants.CAMERA_AIM_LIFT
			return CFrame.lookAt(
				Vector3.new(0, aimY, Constants.PLANE_Z + Constants.CAMERA_DISTANCE),
				Vector3.new(0, aimY, Constants.PLANE_Z)
			)
		end

		local camera = workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = Constants.CAMERA_FOV
		camera.CFrame = target()

		RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value, function(deltaTime)
			local current = workspace.CurrentCamera
			-- Respawns and Studio can hand the camera back to the default script;
			-- reclaiming it each frame is cheaper than watching for that.
			if current.CameraType ~= Enum.CameraType.Scriptable then
				current.CameraType = Enum.CameraType.Scriptable
			end
			-- Framerate-independent exponential follow: the tower can grow by a
			-- whole block between frames and this stays smooth either way.
			local alpha = 1 - math.exp(-Constants.CAMERA_LERP * deltaTime)
			current.CFrame = current.CFrame:Lerp(target(), alpha)
		end)
	end)
end

return TowerCameraController
