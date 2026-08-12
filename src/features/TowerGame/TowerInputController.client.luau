-- Keyboard + gamepad presentation for TowerGame.
--
-- ContextActionService binds one action per intent across every input device it
-- covers, so PC and console are the same three lines. Touch is deliberately NOT
-- handled here: the HUD renders real skinned buttons for it (TowerHUD) rather
-- than CAS's default touch buttons, so mobile gets the same look as everything
-- else in the game.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)

-- Client-realm sibling (StarterPlayerScripts.Features.TowerGame.TowerController).
local TowerController = require(script.Parent.TowerController)

local TowerInputController = {}

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

	bind("TowerMoveLeft", TowerController.moveLeft, Enum.KeyCode.A, Enum.KeyCode.Left, Enum.KeyCode.DPadLeft)
	bind("TowerMoveRight", TowerController.moveRight, Enum.KeyCode.D, Enum.KeyCode.Right, Enum.KeyCode.DPadRight)
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
