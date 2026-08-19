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

-- Client-realm siblings (StarterPlayerScripts.Features.TowerGame.*).
local TowerController = require(script.Parent.TowerController)
-- Subscribed to alongside the classic store: in PVP the piece being handed out
-- is announced on the match packet, not the turn packet.
local PvpController = require(script.Parent.PvpController)
-- The landing-preview toggle. Read at build time, so flipping it takes effect on
-- the next turn rather than mid-aim.
local SettingsController = require(script.Parent.Parent.Settings.SettingsController)

local TowerAimController = {}

-- Starts before the input controllers so they always have somewhere to talk to.
TowerAimController.Priority = 10

local preview: Model? = nil
-- The ghost showing where the piece would land if dropped now. Local to the
-- holder — everyone else seeing every aim would be a wall of translucent blocks,
-- and the point of it is to answer "will this fit", which is the holder's
-- question alone.
local landing: Model? = nil
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
-- World X of the lane this turn is being played in, captured at setup.
--
-- `aimX` is measured from *here*, not from the world origin, and so is every
-- number that goes over the wire — which is what makes the server's clamp mean
-- "inside your own lane" rather than "inside the middle of the arena". In the
-- classic game it's 0 and every line below reduces to what it was.
--
-- Captured once per turn rather than read per frame: a lane can't change under a
-- piece, and reading it live would let a mid-turn state packet slide the piece
-- sideways.
local laneX = 0

local function pieceCFrame(): CFrame
	return CFrame.new(laneX + aimX, baseY, Constants.PLANE_Z)
		* CFrame.Angles(0, 0, -aimTurns * math.pi / 2)
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
	-- And the tells, for exactly the same reason the plate is here. A Highlight is
	-- drawn from geometry rather than from how that geometry looks, so
	-- LocalTransparencyModifier doesn't reach one either: the real piece stayed
	-- hidden and its tell did not, leaving the holder steering a preview that wore
	-- its own tell while a second copy hung a frame behind at the server's
	-- position. Two offset outlines of the same block, which reads as the block
	-- wearing a crooked clone of itself — and is worst on the loudest tells, so a
	-- Bomb showed it plainly and a quiet type barely at all.
	--
	-- Only the holder's own view is touched. Everyone else is watching the real
	-- piece and should see its tell the whole way down.
	--
	-- By class rather than by name, so the second tell a glued block wears is
	-- covered without this file having heard of it.
	for _, child in model:GetChildren() do
		if child:IsA("Highlight") then
			child.Enabled = not hidden
		end
	end
end

-- --------------------------------------------------------- the landing ghost --
--
-- Where the piece would come to rest if it were dropped right now, drawn as a
-- translucent copy of it.
--
-- It answers the one question aiming actually poses — "does this fit there?" —
-- which the piece hanging in the air above the tower can't. Purely local: it's
-- built on the client, shown only to the holder, and the server never learns it
-- exists.
--
-- The drop is solved by raycasting *down from each cell* and taking the shortest
-- fall. Per-cell rather than from the model's pivot because an L or a T has
-- cells at different depths, and the piece stops when its *lowest* cell lands —
-- casting from the middle would sink the ghost into whatever is under the
-- overhang.

local landingParams = RaycastParams.new()
landingParams.FilterType = Enum.RaycastFilterType.Exclude

local function buildLanding(source: Model)
	if landing then
		landing:Destroy()
		landing = nil
	end
	if not SettingsController.get(Constants.SETTING_LANDING_PREVIEW) then
		return
	end

	local ghost = source:Clone()
	ghost.Name = "LandingPreview"
	for _, part in ghost:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Anchored = true
			part.Transparency = Constants.LANDING_TRANSPARENCY
			part.Material = Enum.Material.SmoothPlastic
			part.CastShadow = false
		elseif part:IsA("Humanoid") or part:IsA("Highlight") or part:IsA("BillboardGui") then
			-- A ghost is scenery. A Humanoid would try to stand it up, and the
			-- type tell and name plate already exist on the real piece above.
			part:Destroy()
		end
	end
	ghost.Parent = workspace
	landing = ghost
end

local function updateLanding(aimed: CFrame)
	local ghost = landing
	if ghost == nil then
		return
	end

	-- Everything the cast must ignore: the real piece (it's directly above), the
	-- local preview, and the ghost itself.
	local exclude: { Instance } = { ghost }
	if serverPiece then
		table.insert(exclude, serverPiece)
	end
	if preview then
		table.insert(exclude, preview)
	end
	landingParams.FilterDescendantsInstances = exclude

	ghost:PivotTo(aimed)

	local drop = math.huge
	for _, part in ghost:GetDescendants() do
		if not part:IsA("BasePart") then
			continue
		end
		local from = part.Position - Vector3.new(0, part.Size.Y / 2, 0)
		local hit = workspace:Raycast(from, Vector3.new(0, -Constants.LANDING_MAX_DROP, 0), landingParams)
		drop = math.min(drop, if hit then (from - hit.Position).Magnitude else Constants.LANDING_MAX_DROP)
	end

	-- Nothing underneath at all (aimed off the side of the platform): the ghost
	-- would sit at the bottom of the cast, which is meaningless, so hide it.
	if drop >= Constants.LANDING_MAX_DROP then
		for _, part in ghost:GetDescendants() do
			if part:IsA("BasePart") then
				part.Transparency = 1
			end
		end
		return
	end

	for _, part in ghost:GetDescendants() do
		if part:IsA("BasePart") then
			part.Transparency = Constants.LANDING_TRANSPARENCY
		end
	end
	ghost:PivotTo(aimed - Vector3.new(0, drop, 0))
end

local function teardown()
	active = false
	if preview then
		preview:Destroy()
		preview = nil
	end
	if landing then
		landing:Destroy()
		landing = nil
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
	laneX = TowerController.laneOriginX()
	aimX = piece:GetPivot().Position.X - laneX
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
	-- Built from the *server* piece, not the preview: the preview has already
	-- had its Humanoid stripped and its parts made non-colliding, and the ghost
	-- wants the piece's real shape to cast from.
	buildLanding(piece)
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

-- Absolute placement from the mouse. `x` is a *world* X — the pointer controller
-- casts onto the play plane and has no idea which lane the player is in — so it's
-- brought back to the lane before it's clamped. Point at somebody else's tower
-- and your own piece stops at the edge of your lane, which is the honest answer.
function TowerAimController.pointAt(x: number)
	if not active or x ~= x then
		return
	end
	-- Pointing wins over holding; otherwise the two fight every frame.
	steerDir = 0
	aimX = math.clamp(x - laneX, -Constants.STEER_LIMIT_X, Constants.STEER_LIMIT_X)
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
	local aimed = pieceCFrame()
	if preview then
		preview:PivotTo(aimed)
	end
	updateLanding(aimed)

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
	local wasAiming = false

	-- Fires on either mode's state packet. `isAiming` is the mode-agnostic answer
	-- — my turn in classic, my lane's piece in PVP — so this one handler covers
	-- both and neither store has to know the other exists.
	local function onStateChanged()
		local isAiming = TowerController.isAiming()
		if isAiming == wasAiming then
			return
		end
		wasAiming = isAiming

		if not isAiming then
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
		-- Set before `setup` yields on the piece replicating, so a placement sent
		-- in that window is already measured from the right lane.
		laneX = TowerController.laneOriginX()
		task.spawn(setup)
	end

	TowerController.DataChanged:Connect(onStateChanged)
	PvpController.DataChanged:Connect(onStateChanged)

	RunService.RenderStepped:Connect(step)
end

return TowerAimController
