-- Keyboard + gamepad presentation for TowerGame.
--
-- ContextActionService binds one action per intent across every input device it
-- covers, so PC and console are the same three lines. Touch is deliberately NOT
-- handled here: the HUD renders real skinned buttons for it (TowerHUD) rather
-- than CAS's default touch buttons, so mobile gets the same look as everything
-- else in the game.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)

-- Client-realm sibling (StarterPlayerScripts.Features.TowerGame.TowerController).
local TowerController = require(script.Parent.TowerController)

local TowerInputController = {}

-- Which directions are physically down right now. Tracked so releasing one of
-- two held keys resumes the other instead of stopping the piece dead.
local pressed = { [-1] = false, [1] = false }

local function sendHeld()
	local dir = 0
	if pressed[-1] then
		dir -= 1
	end
	if pressed[1] then
		dir += 1
	end
	TowerController.setSteer(dir)
end

-- Movement is a held direction: press starts the glide, release stops it.
local function bindHold(name: string, dir: number, ...: Enum.KeyCode)
	ContextActionService:BindAction(name, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			pressed[dir] = true
		elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			pressed[dir] = false
		else
			return Enum.ContextActionResult.Pass
		end
		sendHeld()
		return Enum.ContextActionResult.Sink
	end, false, ...)
end

-- Fires on key-down only, and sinks so a held key doesn't repeat-fire the intent.
local function bind(name: string, intent: () -> (), ...: Enum.KeyCode)
	ContextActionService:BindAction(name, function(_, inputState)
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		intent()
		return Enum.ContextActionResult.Sink
	end, false, ...)
end

function TowerInputController.Start()
	if not Constants.Presentations.input then
		return
	end

	bindHold("TowerMoveLeft", -1, Enum.KeyCode.A, Enum.KeyCode.Left, Enum.KeyCode.DPadLeft)
	bindHold("TowerMoveRight", 1, Enum.KeyCode.D, Enum.KeyCode.Right, Enum.KeyCode.DPadRight)

	-- Held movement has one failure mode: a key-down with no matching key-up
	-- (alt-tabbing mid-glide, a gamepad disconnecting) would leave the piece
	-- sliding until it hits the travel limit. Losing focus force-releases.
	UserInputService.WindowFocusReleased:Connect(function()
		pressed[-1] = false
		pressed[1] = false
		sendHeld()
	end)

	-- A player can already be holding a direction when their turn starts — they
	-- were waiting on the previous player. No input event fires for a key that
	-- never moved, and the server clears the steer direction on every new turn,
	-- so re-assert what's held the moment the piece becomes ours.
	local wasMyTurn = false
	TowerController.DataChanged:Connect(function()
		local isMyTurn = TowerController.isMyTurn()
		if isMyTurn and not wasMyTurn then
			sendHeld()
		end
		wasMyTurn = isMyTurn
	end)
	bind("TowerRotate", function()
		TowerController.rotate(true)
	end, Enum.KeyCode.W, Enum.KeyCode.Up, Enum.KeyCode.R, Enum.KeyCode.ButtonY)
	bind(
		"TowerDrop",
		TowerController.drop,
		Enum.KeyCode.Space,
		Enum.KeyCode.S,
		Enum.KeyCode.Down,
		Enum.KeyCode.ButtonA
	)
end

return TowerInputController
