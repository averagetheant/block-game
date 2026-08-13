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

local BlockLabel = require(ReplicatedStorage.Features.TowerGame.BlockLabel)
local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)
local Sfx = require(ReplicatedStorage.Features.TowerGame.Sfx)

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

-- Hide/show the authoritative piece for this client only.
-- LocalTransparencyModifier is render-side, so the server never sees it and no
-- other player is affected.
--
-- Two things learned the hard way about this property:
--   * it doesn't stick — something resets it, so hiding has to be re-applied
--     from the render loop rather than set once;
--   * it doesn't reliably reset *itself* either, so the hide must be explicitly
--     undone. Skipping that is what left the first block permanently invisible.
local function setServerPieceHidden(hidden: boolean)
	local model = serverPiece
	if model == nil then
		return
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
	-- The name plate is a GUI, so LocalTransparencyModifier doesn't reach it and
	-- the holder would read two of them — the smooth one on the preview and the
	-- real one lagging a frame behind. Disabling an instance client-side is local
	-- to this player, same as the transparency above.
	local label = BlockLabel.find(model)
	if label then
		label.Enabled = not hidden
	end
end

local function teardown()
	active = false
	if preview then
		preview:Destroy()
		preview = nil
	end
	-- Give the piece back before letting go of it, or it stays invisible for the
	-- rest of the round.
	setServerPieceHidden(false)
	serverPiece = nil
	steerDir = 0
	lastSentX = math.huge
	lastSentTurns = -1
end

-- The piece the server just handed us, found by the attribute it stamps on it.
--
-- The anchored check is belt-and-braces: a held piece is always anchored, so even
-- if the attribute were ever left on a released block, we can't mistake a live
-- physics block for our piece and start puppeting it.
local function findOwnPiece(): Model?
	local arena = workspace:FindFirstChild(Constants.ARENA_NAME)
	if arena == nil then
		return nil
	end
	for _, child in arena:GetChildren() do
		if not child:IsA("Model") or child:GetAttribute(Constants.HELD_ATTRIBUTE) ~= Players.LocalPlayer.UserId then
			continue
		end
		local part = child:FindFirstChildWhichIsA("BasePart")
		if part and part.Anchored then
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
	-- Descendants, not children: a Noob hangs its accessories one level deeper,
	-- and an unanchored hat on an anchored preview drops through the floor.
	for _, part in clone:GetDescendants() do
		if part:IsA("BasePart") then
			-- The real piece is the one that collides; this is pure decoration.
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Anchored = true
		end
	end
	-- A preview is scenery. Left in, a rig's Humanoid would try to stand it up
	-- and animate it against a model the client is puppeting by hand.
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:Destroy()
	end
	clone.Parent = workspace
	preview = clone

	clone:PivotTo(pieceCFrame())
end

-- ------------------------------------------------------------------ intents --

-- Held direction, integrated in the render loop below. Anything in [-1, 1]: a
-- key sends a full ±1, a thumbstick sends its actual deflection, so a gentle
-- push on the stick nudges the piece and a full one moves it at STEER_SPEED.
-- Clamped rather than rounded — rounding is what would throw the analog range
-- away and make the stick behave like a D-pad.
function TowerAimController.setSteer(dir: number)
	steerDir = if dir ~= dir then 0 else math.clamp(dir, -1, 1)
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
	-- The dropper's own confirmation cue. Everyone else hears the world-space
	-- "Drop" the server plays on the piece.
	Sfx.play("Drop2")
	teardown()
end

-- ----------------------------------------------------------------- the loop --

local function step(deltaTime: number)
	if not active then
		return
	end

	-- X is ours, Y is the server's. It parks the piece clear of the tower and
	-- lifts it again if the tower grows underneath (a Noob climbing, a Clone
	-- landing), so the preview reads the altitude back every frame instead of
	-- keeping the one it was handed — otherwise the holder aims a piece that is
	-- drawn lower than the one that will actually fall.
	local model = serverPiece
	if model then
		baseY = model:GetPivot().Position.Y
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
	setServerPieceHidden(true)
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
