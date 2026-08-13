-- Keyboard + gamepad presentation for TowerGame.
--
-- ContextActionService binds one action per intent across every input device it
-- covers, so PC and console are the same few lines. Touch is deliberately NOT
-- handled here: the HUD renders real skinned buttons for it (TowerHUD) rather
-- than CAS's default touch buttons, so mobile gets the same look as everything
-- else in the game.
--
-- Every bind here is an *alternative* to the others, never a mode: rotate is on
-- W / Up / R / ButtonY and the scroll wheel at once, and a player can move
-- between them mid-turn without the game caring which one they used last.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)

-- Client-realm siblings (StarterPlayerScripts.Features.TowerGame.*).
local TowerAimController = require(script.Parent.TowerAimController)
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
	TowerAimController.setSteer(dir)
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

	bind("TowerRotate", TowerAimController.rotate, Enum.KeyCode.W, Enum.KeyCode.Up, Enum.KeyCode.R, Enum.KeyCode.ButtonY)

	-- Scroll wheel as an alternate rotate: the hand that's already aiming with the
	-- mouse (TowerPointerController) shouldn't have to reach for a key to spin the
	-- piece. It can't ride on `bind` — a wheel notch arrives as a `Change` with the
	-- direction in Position.Z, never as a `Begin`. Both directions turn the same
	-- way, because `rotate` is a single quarter-turn and the keys do the same.
	-- Sinking it costs nothing here: the camera is scriptable, so there's no
	-- default zoom to preserve.
	ContextActionService:BindAction("TowerRotateScroll", function(_, inputState)
		if inputState ~= Enum.UserInputState.Change then
			return Enum.ContextActionResult.Pass
		end
		TowerAimController.rotate()
		return Enum.ContextActionResult.Sink
	end, false, Enum.UserInputType.MouseWheel)
	bind(
		"TowerDrop",
		TowerAimController.drop,
		Enum.KeyCode.Space,
		Enum.KeyCode.S,
		Enum.KeyCode.Down,
		Enum.KeyCode.ButtonA
	)

	-- A player can already be holding a direction when their turn starts — they
	-- were waiting on the previous player. No input event fires for a key that
	-- never moved, and the aim controller resets its direction on every new turn,
	-- so re-assert what's held the moment the piece becomes ours.
	local wasMyTurn = false
	TowerController.DataChanged:Connect(function()
		local isMyTurn = TowerController.isMyTurn()
		if isMyTurn and not wasMyTurn then
			sendHeld()
		end
		wasMyTurn = isMyTurn
	end)
end

return TowerInputController
