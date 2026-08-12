-- Local aiming for the holder. This is the file that makes placement feel
-- instant.
--
-- The problem it solves: the piece is a server-owned Model, so moving it means a
-- round trip, and the holder sees their own input arrive late. The fix is the
-- standard one — the holder renders a *local copy* that follows input at frame
-- rate and hides the real piece for themselves, while the real piece keeps
-- moving (a little behind) for everyone else.
--
--   holder    → local preview, zero latency, drives everything
--   spectator → the real server piece, updated at Constants.AIM_INTERVAL
--   server    → clamps whatever the holder reports; still owns the outcome
--
-- Nothing here is authoritative. The client picks where it *wants* the piece;
-- TowerService decides where it actually goes, and the drop carries its final
-- placement so what the holder saw is what falls.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)

-- Client-realm sibling (StarterPlayerScripts.Features.TowerGame.TowerController).
local TowerController = require(script.Parent.TowerController)

local TowerAimController = {}

-- Starts before the input controllers so they always have somewhere to talk to.
TowerAimController.Priority = 10

local preview: Model? = nil
local serverPiece: Model? = nil
-- True for the whole of our turn. Intents gate on this rather than on `preview`
-- so a preview that failed to appear can't brick the turn — worst case aiming
-- goes back to feeling networked, which is what it did before this file existed.
local active = false
-- Where the holder currently wants the piece, in the same terms the server
-- speaks: an X on the play plane and a number of quarter turns.
local aimX = 0
local aimTurns = 0
-- Held direction from the keyboard/gamepad, integrated locally each frame.
local steerDir = 0
local baseY = 0
local lastSentAt = 0
local lastSentX = math.huge
local lastSentTurns = -1

local function pieceCFrame(): CFrame
	return CFrame.new(aimX, baseY, Constants.PLANE_Z) * CFrame.Angles(0, 0, -aimTurns * math.pi / 2)
end

-- Hide the authoritative piece for this client only. LocalTransparencyModifier is
-- render-side, so the server never sees it and no other player is affected — but
-- the engine resets it every frame for anything that isn't the local character,
-- so this has to be re-applied from the render loop rather than set once.
--
-- That reset is a feature here: the moment we stop calling this the piece
-- reappears on its own, so a released block can't get stuck invisible.
local function hideServerPiece()
	local model = serverPiece
	if model == nil then
		return
	end
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			part.LocalTransparencyModifier = 1
		end
	end
end

local function teardown()
	active = false
	if preview then
		preview:Destroy()
		preview = nil
	end
	-- No un-hide needed: dropping `serverPiece` stops the per-frame re-apply and
	-- the engine restores the part on its own next frame.
	serverPiece = nil
	steerDir = 0
	lastSentX = math.huge
	lastSentTurns = -1
end

-- The piece the server just handed us, found by the attribute it stamps on it.
local function findOwnPiece(): Model?
	local arena = workspace:FindFirstChild(Constants.ARENA_NAME)
	if arena == nil then
		return nil
	end
	for _, child in arena:GetChildren() do
		if child:IsA("Model") and child:GetAttribute(Constants.HELD_ATTRIBUTE) == Players.LocalPlayer.UserId then
			return child
		end
	end
	return nil
end

-- The state packet and the piece replicate independently, so the piece may not
-- have arrived when our turn is announced. Wait for it briefly.
local function waitForOwnPiece(): Model?
	local deadline = os.clock() + 3
	repeat
		local piece = findOwnPiece()
		if piece then
			return piece
		end
		task.wait(0.05)
	until os.clock() > deadline or not active
	return nil
end

local function setup()
	local piece = waitForOwnPiece()
	-- The turn could have ended while we waited.
	if piece == nil or not active then
		return
	end

	serverPiece = piece
	aimX = piece:GetPivot().Position.X
	aimTurns = 0
	baseY = piece:GetPivot().Position.Y

	-- A clone parented on the client stays client-only, so this costs the server
	-- and every other player nothing.
	local clone = piece:Clone()
	clone.Name = "LocalPreview"
	for _, part in clone:GetChildren() do
		if part:IsA("BasePart") then
			-- The real piece is the one that collides; this is pure decoration.
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Anchored = true
		end
	end
	clone.Parent = workspace
	preview = clone

	clone:PivotTo(pieceCFrame())
end

-- ------------------------------------------------------------------ intents --

-- Held direction: -1, 0 or 1. Integrated in the render loop below.
function TowerAimController.setSteer(dir: number)
	steerDir = if dir > 0 then 1 elseif dir < 0 then -1 else 0
end

-- Absolute placement from the mouse.
function TowerAimController.pointAt(x: number)
	if not active or x ~= x then
		return
	end
	-- Pointing wins over holding; otherwise the two fight every frame.
	steerDir = 0
	aimX = math.clamp(x, -Constants.STEER_LIMIT_X, Constants.STEER_LIMIT_X)
end

function TowerAimController.rotate()
	if not active then
		return
	end
	aimTurns = (aimTurns + 1) % 4
end

function TowerAimController.drop()
	if not active then
		return
	end
	-- Send the placement with the drop so the piece lands where it's being shown,
	-- not where the last stream update got to.
	TowerController.release(aimX, aimTurns)
	teardown()
end

-- A touch tap has no key-up, so it moves a fixed distance instead of holding.
function TowerAimController.nudge(dir: number)
	if not active then
		return
	end
	local step = dir * Constants.STEER_SPEED * Constants.TOUCH_NUDGE_SECONDS
	aimX = math.clamp(aimX + step, -Constants.STEER_LIMIT_X, Constants.STEER_LIMIT_X)
end

-- ----------------------------------------------------------------- the loop --

local function step(deltaTime: number)
	if not active then
		return
	end

	if steerDir ~= 0 then
		aimX = math.clamp(
			aimX + steerDir * Constants.STEER_SPEED * deltaTime,
			-Constants.STEER_LIMIT_X,
			Constants.STEER_LIMIT_X
		)
	end

	-- The preview moves every frame regardless of the network, and the real piece
	-- stays hidden behind it.
	hideServerPiece()
	if preview then
		preview:PivotTo(pieceCFrame())
	end

	local now = os.clock()
	if now - lastSentAt < Constants.AIM_INTERVAL then
		return
	end
	if math.abs(aimX - lastSentX) < Constants.AIM_EPSILON and aimTurns == lastSentTurns then
		return
	end

	lastSentAt = now
	lastSentX = aimX
	lastSentTurns = aimTurns
	TowerController.place(aimX, aimTurns)
end

function TowerAimController.Start()
	local wasMyTurn = false

	TowerController.DataChanged:Connect(function()
		local isMyTurn = TowerController.isMyTurn()
		if isMyTurn == wasMyTurn then
			return
		end
		wasMyTurn = isMyTurn

		if not isMyTurn then
			teardown()
			return
		end

		-- Aiming is live immediately; the preview catches up once the piece has
		-- replicated. Reset the placement first so a stale aim from last turn
		-- can't be sent before setup runs.
		active = true
		aimX = 0
		aimTurns = 0
		steerDir = 0
		task.spawn(setup)
	end)

	RunService.RenderStepped:Connect(step)
end

return TowerAimController
