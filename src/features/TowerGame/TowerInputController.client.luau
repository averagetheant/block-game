-- Keyboard + gamepad presentation for TowerGame.
--
-- ContextActionService binds one action per intent across every input device it
-- covers, so PC and console are the same few lines. Touch is deliberately NOT
-- handled here: the HUD renders real skinned buttons for it (TowerHUD) rather
-- than CAS's default touch buttons, so mobile gets the same look as everything
-- else in the game.
--
-- Every bind here is an *alternative* to the others, never a mode: rotate is on
-- W / Up / R / ButtonY, the scroll wheel and the right stick at once, and a
-- player can move between them mid-turn without the game caring which one they
-- used last.
--
-- The thumbsticks are the one thing CAS can't express, because it delivers a
-- stick as a stream of Change events and both of ours need frame state rather
-- than events: the left stick's steer is an analog value integrated per frame,
-- and the right stick's rotate is an edge that needs hysteresis. Both are read
-- from `GetGamepadState` in one Heartbeat instead.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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

-- The deflection of one stick, or Vector2.zero when there's no gamepad. Read
-- fresh each frame rather than cached off an event, because a stick held at a
-- constant angle fires no events at all and would look like a released one.
local function stickPosition(keyCode: Enum.KeyCode): Vector2
	for _, gamepad in UserInputService:GetConnectedGamepads() do
		for _, input in UserInputService:GetGamepadState(gamepad) do
			if input.KeyCode == keyCode then
				return Vector2.new(input.Position.X, input.Position.Y)
			end
		end
	end
	return Vector2.zero
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

	bindHold(
		"TowerMoveLeft",
		-1,
		Enum.KeyCode.A,
		Enum.KeyCode.Left,
		Enum.KeyCode.DPadLeft,
		-- The bumpers: the pad's other pair of "one on each side" buttons, which
		-- is what makes them read as left/right without being explained.
		Enum.KeyCode.ButtonL1
	)
	bindHold(
		"TowerMoveRight",
		1,
		Enum.KeyCode.D,
		Enum.KeyCode.Right,
		Enum.KeyCode.DPadRight,
		Enum.KeyCode.ButtonR1
	)

	-- Held movement has one failure mode: a key-down with no matching key-up
	-- (alt-tabbing mid-glide, a gamepad disconnecting) would leave the piece
	-- sliding until it hits the travel limit. Losing focus force-releases.
	UserInputService.WindowFocusReleased:Connect(function()
		pressed[-1] = false
		pressed[1] = false
		sendHeld()
	end)

	bind(
		"TowerRotate",
		TowerAimController.rotate,
		Enum.KeyCode.W,
		Enum.KeyCode.Up,
		Enum.KeyCode.R,
		Enum.KeyCode.ButtonY,
		-- Clicking the left stick in. The thumb steering the piece is already
		-- there, so a rotate costs no reach.
		Enum.KeyCode.ButtonL3,
		-- Left trigger. Roblox reports L2/R2 as analog *and* as buttons, and this
		-- only ever acts on Begin, so a trigger press is one quarter turn rather
		-- than a stream of them as it travels.
		Enum.KeyCode.ButtonL2
	)

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
		Enum.KeyCode.ButtonA,
		-- Right trigger. The drop is the one committing action on the pad, and a
		-- trigger is the one input you can't hit by accident with a resting hand.
		Enum.KeyCode.ButtonR2
	)

	-- The left stick. Polled rather than bound, because a stick held at a constant
	-- angle fires no events at all and would look like a released one.
	--
	-- Steering hands control back and forth rather than fighting: while the stick
	-- is off-centre it owns the steer, and the frame it returns to centre it
	-- re-asserts whatever the D-pad or bumpers are holding. Without that handover
	-- a stick release would leave the piece gliding on the last analog value, or
	-- stomp a direction the player was still holding.
	--
	-- The *right* stick is deliberately not read here: it drives the player's
	-- cursor (see docs/game/Cursors.md), and on console that cursor is the only
	-- pointer they have.
	local stickSteering = false

	RunService.Heartbeat:Connect(function()
		local steer = stickPosition(Enum.KeyCode.Thumbstick1).X
		if math.abs(steer) >= Constants.GAMEPAD_STEER_DEADZONE then
			stickSteering = true
			TowerAimController.setSteer(steer)
		elseif stickSteering then
			stickSteering = false
			sendHeld()
		end
	end)

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
