-- Pointing presentation for TowerGame: the piece goes where you point, by mouse
-- on PC and by tap or drag on touch. An *alternative* to the keyboard and the
-- steering stick, not a replacement — all of them stay live, and they don't
-- fight because this only speaks while the pointer is actually moving, and the
-- server drops any held steer direction when an aim arrives.
--
-- A pointer is a screen position and the piece lives on a world plane, so every
-- frame that matters we cast it into the world and solve for where it crosses
-- Z = PLANE_Z. That's the X the piece wants. Both devices share that solve.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)

-- Client-realm siblings (StarterPlayerScripts.Features.TowerGame.*).
local TowerAimController = require(script.Parent.TowerAimController)
local TowerController = require(script.Parent.TowerController)

local TowerPointerController = {}

-- Screen movement (in pixels) that counts as "the player moved the mouse".
local MOVE_THRESHOLD = 1

-- Where a screen point crosses the play plane, or nil if it never does (the
-- camera is level with the plane, or the plane is behind the viewer). Shared by
-- the mouse and the touch handlers — both are a screen position that has to be
-- turned into an X on the world plane.
local function planeXAt(screenX: number, screenY: number): number?
	local camera = workspace.CurrentCamera
	if camera == nil then
		return nil
	end

	local ray = camera:ScreenPointToRay(screenX, screenY)
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

-- Touch: tapping or dragging the world sends the piece to where you touched.
--
-- The subtlety is which touches are *ours*. `gameProcessed` is true for a touch
-- on a GUI control — but only while the finger is still over it. Drag the
-- steering stick to the edge of the screen and the moves start arriving
-- unprocessed, at which point this would happily read them as "point the piece
-- here" and snap it to wherever the thumb had got to. That's what made the piece
-- jump to the edge of the arena whenever the stick was pushed to either end.
--
-- So a gesture is claimed once, at InputBegan, and that claim holds for the
-- whole life of the InputObject. A touch that starts on the HUD belongs to the
-- HUD until the finger lifts, wherever it wanders.
local claimedByGui: { [InputObject]: boolean } = {}

local function startTouch()
	local function moveTo(input: InputObject)
		if not TowerController.isMyTurn() then
			return
		end
		local x = planeXAt(input.Position.X, input.Position.Y)
		if x == nil then
			return
		end
		TowerAimController.pointAt(x)
	end

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if gameProcessed then
			claimedByGui[input] = true
			return
		end
		moveTo(input)
	end)

	-- A held finger keeps aiming, so a tap and a drag are the same gesture and
	-- neither needs explaining. `gameProcessed` is deliberately *not* re-checked
	-- here: a drag that began on the world shouldn't die crossing a button, and
	-- one that began on the HUD is already excluded by its claim.
	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch or claimedByGui[input] then
			return
		end
		moveTo(input)
	end)

	UserInputService.InputEnded:Connect(function(input)
		claimedByGui[input] = nil
	end)
end

function TowerPointerController.Start()
	if not Constants.Presentations.pointer then
		return
	end

	if UserInputService.TouchEnabled then
		startTouch()
	end

	-- The mouse half. A touch device without a mouse stops here: it has the tap
	-- handler above instead.
	if not UserInputService.MouseEnabled then
		return
	end

	local mouse = Players.LocalPlayer:GetMouse()
	local lastScreen: Vector2? = nil

	-- Every frame the mouse moves, no throttle: this only writes a local number,
	-- and the aim controller is what decides how often the server hears about it.
	-- Throttling here would put the steppiness back into the thing we're smoothing.
	RunService.RenderStepped:Connect(function()
		if not TowerController.isMyTurn() then
			-- Re-baseline while we wait, so the piece doesn't snap to a stale
			-- pointer position the instant the turn arrives.
			lastScreen = nil
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

		local x = planeXAt(mouse.X, mouse.Y)
		if x == nil then
			return
		end
		TowerAimController.pointAt(x)
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
		TowerAimController.drop()
	end)
end

return TowerPointerController
