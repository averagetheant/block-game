-- Client core for Cursors: works out where *this* player's cursor is, reports
-- it, and keeps the last known position of everyone else's.
--
-- Headless (see docs/game/headless-core.md) — it holds state and speaks the
-- wire, and it draws nothing. CursorsWorldInteraction is what turns this into
-- something on screen.
--
-- Three input devices, one answer. Whatever the player is holding, the output is
-- the same thing: a point on the play plane, in world studs.
--
--   * Mouse — where the pointer crosses the plane. Continuous; there's always a
--     cursor.
--   * Touch — where a held finger crosses the plane. There is no hover on a
--     phone, so the cursor only exists while a finger is down, and lifting it
--     stops reporting (the server then times the cursor out).
--   * Gamepad — the right stick moves the cursor, because a console has no
--     pointer to project at all. It's integrated per frame rather than
--     projected, so it needs a remembered position of its own.
--
-- The local cursor is deliberately never drawn: the player already knows where
-- their pointer is, and a system cursor sitting under a second drawn one reads
-- as lag. Reporting still happens — everyone *else* wants to see it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Signal = require(ReplicatedStorage.Packages.Signal)
local Constants = require(ReplicatedStorage.Features.Cursors.Constants)
local Packets = require(ReplicatedStorage.Features.Cursors.Packets)
local TowerConstants = require(ReplicatedStorage.Features.TowerGame.Constants)

-- Client-realm sibling from another feature (StarterPlayerScripts.Features).
local SettingsController = require(script.Parent.Parent.Settings.SettingsController)

local CursorsController = {}

-- After the controllers whose state it reads.
CursorsController.Priority = 35

export type Cursor = {
	userId: number,
	x: number,
	y: number,
}

-- Fires when the set of remote cursors changes. The world presentation listens;
-- nothing else has to poll.
CursorsController.Changed = Signal.new()

local remote: { Cursor } = {}

-- Where the gamepad has driven the cursor to. Only the stick uses this — mouse
-- and touch are projections and carry no memory between frames.
local stickPosition = Vector2.new(0, TowerConstants.BASE_POSITION.Y + 30)

-- The screen position of the finger currently held down, or nil for none. Set
-- by the touch hooks in Start; a phone has no hover, so this being nil is the
-- normal resting state rather than an error.
local touchScreen: Vector2? = nil

-- The local cursor's current position, recomputed every frame. Kept apart from
-- the reporting throttle so the drawing can be smooth while the wire stays slow.
local current: Vector2? = nil

-- Every cursor but the local player's, newest state.
function CursorsController.list(): { Cursor }
	return remote
end

function CursorsController.enabled(): boolean
	return SettingsController.get(Constants.SETTING_ID) ~= false
end

-- Whether the last input worth reading came from a pad. Ignores Focus and
-- TextInput, which fire from window focus and the chat bar and say nothing about
-- what's in the player's hands — the same carve-out TowerView's `deviceOf` makes.
local lastInputWasGamepad = false

-- True when this device drives its cursor with a thumbstick.
--
-- A mouse still outranks a pad, but on *capability* that test was absolute:
-- `GamepadEnabled and not MouseEnabled` is false on every machine that has both,
-- so a PC with a controller plugged in could never move the cursor with the
-- stick no matter what the player did — and Studio always reports a mouse, which
-- made this branch unreachable in a Play test.
--
-- The intent behind that rule was "they're almost certainly still pointing with
-- the mouse", and following the last input they actually used is that intent
-- rather than a proxy for it: the mouse keeps the cursor until the stick is
-- pushed, and the moment it is, the stick takes over. A console has no mouse to
-- disagree with, so it's unconditional there and nothing about it changes.
--
-- This is the convention the rest of the game already follows — see
-- TowerView.useDevice, which switches the controls hint the same way and for the
-- same reason.
function CursorsController.usesStickCursor(): boolean
	if not UserInputService.GamepadEnabled then
		return false
	end
	if not UserInputService.MouseEnabled then
		return true
	end
	return lastInputWasGamepad
end

-- Whether the player sees their own cursor. Deliberately *wider* than
-- `usesStickCursor`: any connected pad gets it, mouse or not.
--
-- The reason to hide it elsewhere is that the cursor is already drawn for you —
-- the system pointer, or your finger — so a second arrow under it reads as lag.
-- A stick has nothing underneath, so hiding it there leaves the player pushing
-- an invisible pointer.
--
-- The invariant that matters is the one-way one: this must never be *narrower*
-- than `usesStickCursor`, or a player could be steering a cursor they can't see.
-- A superset is safe — the worst case is an arrow trailing your own mouse.
function CursorsController.showsOwnCursor(): boolean
	return UserInputService.GamepadEnabled
end

-- The local player's own cursor, or nil when it shouldn't be drawn. Read from
-- the live per-frame value rather than from the server's echo of it: a pointer
-- the player is actively pushing has to answer the stick immediately, and a
-- round trip through the server at SEND_INTERVAL would visibly lag it.
function CursorsController.localCursor(): Vector2?
	if not CursorsController.showsOwnCursor() or not CursorsController.enabled() then
		return nil
	end
	return current
end

-- Where a screen point crosses the play plane, in world studs. The same solve
-- TowerPointerController does for aiming — the pointer is a screen position and
-- the game is a world plane, so something has to cross between them.
local function planePoint(screenX: number, screenY: number): Vector2?
	local camera = workspace.CurrentCamera
	if camera == nil then
		return nil
	end

	local ray = camera:ScreenPointToRay(screenX, screenY)
	local directionZ = ray.Direction.Z
	if math.abs(directionZ) < 1e-4 then
		return nil
	end

	local distance = (TowerConstants.PLANE_Z - ray.Origin.Z) / directionZ
	if distance <= 0 then
		return nil
	end
	return Vector2.new(
		ray.Origin.X + ray.Direction.X * distance,
		ray.Origin.Y + ray.Direction.Y * distance
	)
end

-- The right stick's deflection, or zero when no pad is reporting one.
--
-- Every connected pad is scanned rather than Gamepad1 alone. A controller isn't
-- necessarily on slot 1 — reconnect one, or be the second player to pick one up,
-- and it won't be — and asking only slot 1 got back an empty list, so the loop
-- found no Thumbstick2 and the cursor sat still. Steering kept working the whole
-- time, which is what made this look like a cursor bug rather than a gamepad
-- one: TowerInputController scans the connected pads, and this didn't.
--
-- Read fresh each frame rather than off an event, for the reason that file gives
-- too — a stick held at a constant angle fires no events at all and would look
-- like a released one.
local function rightStick(): Vector2
	for _, gamepad in UserInputService:GetConnectedGamepads() do
		for _, input in UserInputService:GetGamepadState(gamepad) do
			if input.KeyCode == Enum.KeyCode.Thumbstick2 then
				return Vector2.new(input.Position.X, input.Position.Y)
			end
		end
	end
	return Vector2.zero
end

-- Whether the stick was driving the cursor last frame, so a handover from the
-- mouse can pick up where the pointer already is instead of snapping back to
-- wherever the stick was last left.
local usingStick = false

-- The local cursor, or nil when this device isn't pointing at anything right
-- now (a lifted finger, a gamepad with no camera yet).
local function localPoint(deltaTime: number): Vector2?
	if CursorsController.usesStickCursor() then
		if not usingStick then
			usingStick = true
			-- Taking over mid-session: continue from the pointer the player can
			-- already see, not from a stale position from before they put the
			-- mouse down.
			stickPosition = current or stickPosition
		end

		local move = rightStick()
		if move.Magnitude >= Constants.STICK_DEADZONE then
			stickPosition += move * Constants.STICK_SPEED * deltaTime
		end

		-- Held into a corner, the integral would walk off the plane forever. The
		-- server clamps what it's told to these same bounds, so without this the
		-- cursor you're pushing ends up somewhere nobody else sees it.
		stickPosition = Vector2.new(
			math.clamp(stickPosition.X, -Constants.LIMIT_X, Constants.LIMIT_X),
			math.clamp(stickPosition.Y, Constants.MIN_Y, Constants.MAX_Y)
		)
		return stickPosition
	end

	usingStick = false

	-- Touch: only while a finger is actually down. `touchScreen` is nil the rest
	-- of the time, which is what makes lifting a finger stop the cursor.
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		local screen = touchScreen
		if screen == nil then
			return nil
		end
		return planePoint(screen.X, screen.Y)
	end

	local mouse = UserInputService:GetMouseLocation()
	return planePoint(mouse.X, mouse.Y)
end

function CursorsController.Start()
	Packets.State.listen(function(payload)
		local localUserId = Players.LocalPlayer.UserId
		local nextCursors: { Cursor } = {}
		for _, cursor in payload.cursors do
			-- Your own echo is always dropped here. On console the local cursor
			-- *is* drawn, but from `localCursor()` — the live per-frame value —
			-- rather than this round trip, which would visibly lag a pointer the
			-- player is actively pushing.
			if cursor.userId == localUserId then
				continue
			end
			table.insert(nextCursors, cursor)
		end
		remote = nextCursors
		CursorsController.Changed:Fire()
	end)

	-- Which device the player is actually using, for `usesStickCursor` to consult
	-- on a machine that has both a mouse and a pad. Only inputs that say something
	-- about what's in their hands count.
	UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
		if string.match(inputType.Name, "^Gamepad") then
			lastInputWasGamepad = true
		elseif inputType == Enum.UserInputType.Keyboard or string.match(inputType.Name, "^Mouse") then
			lastInputWasGamepad = false
		end
	end)

	-- Touch tracking. `gameProcessed` is what keeps a tap on the HUD's own
	-- buttons — DROP, TURN, the reaction bar — from also flinging the cursor to
	-- wherever that button happens to sit.
	UserInputService.TouchStarted:Connect(function(touch, gameProcessed)
		if gameProcessed then
			return
		end
		touchScreen = Vector2.new(touch.Position.X, touch.Position.Y)
	end)

	UserInputService.TouchMoved:Connect(function(touch, gameProcessed)
		-- A drag that began on the world shouldn't be dropped the moment it
		-- passes over a button, so this only refuses a move it never started.
		if gameProcessed and touchScreen == nil then
			return
		end
		touchScreen = Vector2.new(touch.Position.X, touch.Position.Y)
	end)

	UserInputService.TouchEnded:Connect(function()
		touchScreen = nil
	end)

	-- Where the cursor is, recomputed every frame. Separate from the reporting
	-- below on purpose: the gamepad branch *integrates* the stick by deltaTime,
	-- so sampling it only at SEND_INTERVAL would move the cursor in twelve
	-- chunks a second regardless of frame rate — and on console this is the
	-- pointer the player is watching, so it has to be frame-smooth.
	local since = 0
	local lastSent: Vector2? = nil

	RunService.Heartbeat:Connect(function(deltaTime)
		-- Opting out stops this client *reporting*, not just drawing. Turning
		-- cursors off has to take your own cursor off everyone else's screen too,
		-- or the setting only half means what it says. The server drops a cursor
		-- that stops reporting after STALE_SECONDS, so no goodbye packet is
		-- needed — and that timeout is the whole mechanism here.
		if not CursorsController.enabled() then
			current = nil
			lastSent = nil
			return
		end

		current = localPoint(deltaTime)

		since += deltaTime
		if since < Constants.SEND_INTERVAL then
			return
		end
		since = 0

		local point = current
		if point == nil then
			-- Nothing to report. The server times the cursor out on its own,
			-- which is what makes a lifted finger stop the pointer.
			lastSent = nil
			return
		end
		if lastSent ~= nil and (point - lastSent).Magnitude < Constants.SEND_EPSILON then
			return
		end
		lastSent = point
		Packets.Move.send({ x = point.X, y = point.Y })
	end)
end

return CursorsController
