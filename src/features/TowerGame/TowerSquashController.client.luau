-- Squash and stretch on the block bodies.
--
-- Every block wears one rounded union (see BlockBody) that carries no collision
-- and no mass. This drives that union with a damped spring off impacts: the block
-- stretches along the fall on the way down, compresses on the frame it lands, and
-- overshoots a couple of times on the way back. The cubes underneath never move.
--
-- **Only `Size` and the body weld's `C0` are ever written**, and both are safe for
-- exactly one reason: the body is `CanCollide` false, `CanQuery` false and
-- `Massless`, so the physics engine has no opinion about how big it is. Doing the
-- same to a *cell* would change its mass (breaking the Anvil and Feather
-- densities), change its collision, and corrupt `partTopY` -> `restingTopY` ->
-- `SPAWN_CLEARANCE`, which is how a piece ends up spawning inside the tower.
--
-- Client-side, like the night lights in TowerZoneController: it's a render trick,
-- the server never sees it, and a phone that can't afford it can be handed a
-- setting later without the tower disagreeing between screens.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BlockBody = require(ReplicatedStorage.Features.TowerGame.BlockBody)
local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)

local TowerSquashController = {}

-- The spring. Frequency is sqrt(stiffness) rad/s and `damping` is how fast it
-- dies; around 0.3 of critical leaves two visible overshoots, which is what reads
-- as jelly rather than as the block briefly getting shorter.
local STIFFNESS = 220
local DAMPING = 9

-- Impact detection, measured off the *rendered* motion rather than
-- AssemblyLinearVelocity, so the squish lands on the frame the block visibly
-- stops — replicated velocity for a server-owned part arrives in steps and would
-- fire the wobble a moment after the eye saw the hit.
--
-- The test is what *fraction* of its speed the block lost, not how much: a
-- server-owned part's CFrame replicates at around 20Hz and is interpolated
-- between, so frame-to-frame speed is noisy in proportion to how fast the block
-- is going. A block in clean free fall jitters by 10-20 studs/s a frame while a
-- real landing loses half its speed or more in one, and an absolute threshold
-- can't separate those.
local DECEL_FRACTION = 0.5
local DECEL_FLOOR = 10
local MIN_IMPACT_SPEED = 8
local FULL_IMPACT_SPEED = 90
local MIN_STRENGTH = 0.3
local COOLDOWN = 0.12

local KICK = 5.5
-- Hard clamp on the elongation, or a hard landing turns the block inside out. The
-- body is the same size as the cells it covers, so this is also how far it may
-- visibly overhang them.
local MAX_ELONGATION = 0.3
-- How much the other two axes bulge to make up for the squashed one. Not true
-- volume preservation — that looks like a balloon; this is the animator's version.
local SIDE_GAIN = 0.55
-- Elongation along the fall while it's still in the air. Classic squash and
-- stretch: the stretch on the way down is most of what sells the squash at the
-- bottom of it.
local FALL_STRETCH = 0.16
local FALL_FULL_SPEED = 100

type Tracked = {
	model: Model,
	body: BasePart,
	weld: Weld,
	restC0: CFrame,
	baseSize: Vector3,
	-- Spring state: `e` is signed elongation along `axis` (negative = squashed).
	e: number,
	ev: number,
	axis: number,
	lastPos: Vector3,
	lastSpeed: number,
	lastVelocity: Vector3,
	lastKickAt: number,
	-- A candidate hit waiting on the next frame to confirm it. Interpolation noise
	-- recovers immediately; a block that actually landed is still slow.
	pendingSpeed: number?,
	pendingDirection: Vector3,
	-- Whether the body is currently displaced. A settled tower writes nothing.
	dirty: boolean,
}

local tracked: { [Model]: Tracked } = {}

local function attach(model: Model)
	if tracked[model] then
		return
	end
	local body = BlockBody.of(model)
	if body == nil then
		return
	end
	local weld = BlockBody.weldOf(body)
	if weld == nil then
		return
	end

	local restC0, baseSize = BlockBody.restOf(body)
	tracked[model] = {
		model = model,
		body = body,
		weld = weld,
		restC0 = restC0,
		baseSize = baseSize,
		e = 0,
		ev = 0,
		axis = 2,
		lastPos = body.Position,
		lastSpeed = 0,
		lastVelocity = Vector3.zero,
		lastKickAt = 0,
		pendingSpeed = nil,
		pendingDirection = Vector3.yAxis,
		dirty = false,
	}
end

-- Which of the body's own axes the hit came down. Size is axis-aligned in part
-- space, so an off-angle landing squashes along the nearest axis instead of the
-- true contact normal — invisible at a third of a second.
local function axisFor(entry: Tracked, direction: Vector3): number
	local local_ = entry.body.CFrame:VectorToObjectSpace(direction)
	local x, y, z = math.abs(local_.X), math.abs(local_.Y), math.abs(local_.Z)
	if y >= x and y >= z then
		return 2
	end
	return if x >= z then 1 else 3
end

local function scaleFor(axis: number, e: number): Vector3
	local along = 1 + e
	local across = 1 - e * SIDE_GAIN
	if axis == 1 then
		return Vector3.new(along, across, across)
	elseif axis == 2 then
		return Vector3.new(across, along, across)
	end
	return Vector3.new(across, across, along)
end

-- Resizing a part grows it about its own centre, which would lift a landing block
-- off the surface it just hit by half of whatever it squashed — the compression
-- has to happen *downward*, onto the contact. So the weld's C0 is shifted by
-- exactly what the scale took off the axis, in the direction the hit came from.
local function write(entry: Tracked, e: number)
	local scale = scaleFor(entry.axis, e)
	entry.body.Size = entry.baseSize * scale

	local lost = entry.baseSize * (Vector3.one - scale)
	local shift = Vector3.zero
	local sign = if entry.pendingDirection.Y > 0 then -1 else 1
	if entry.axis == 1 then
		shift = Vector3.new(lost.X * 0.5 * sign, 0, 0)
	elseif entry.axis == 2 then
		shift = Vector3.new(0, -lost.Y * 0.5, 0)
	else
		shift = Vector3.new(0, 0, lost.Z * 0.5 * sign)
	end
	entry.weld.C0 = entry.restC0 * CFrame.new(shift)
end

local function step(entry: Tracked, delta: number, now: number)
	local body = entry.body

	-- Rendered velocity, not the replicated one. Anchored bodies are skipped
	-- outright: a held piece is anchored and steered by the server, and letting go
	-- of the steer stick is a hard stop that would otherwise read as a landing.
	local position = body.Position
	local velocity = (position - entry.lastPos) / delta
	local speed = if body.Anchored then 0 else velocity.Magnitude
	entry.lastPos = position

	-- Confirm or discard last frame's candidate before looking for a new one. A
	-- block that really landed is still slow a frame later; an interpolation
	-- artifact is back up to speed.
	local hit = false
	local pending = entry.pendingSpeed
	if pending then
		entry.pendingSpeed = nil
		if speed <= pending * (1 - DECEL_FRACTION) then
			local strength = math.clamp(
				(pending - MIN_IMPACT_SPEED) / (FULL_IMPACT_SPEED - MIN_IMPACT_SPEED),
				MIN_STRENGTH,
				1
			)
			entry.axis = axisFor(entry, entry.pendingDirection)
			-- Negative: the first thing a landing does is compress.
			entry.ev -= KICK * strength
			entry.lastKickAt = now
			hit = true
		end
	end

	local lost = entry.lastSpeed - speed
	if
		not hit
		and lost >= DECEL_FLOOR
		and lost >= entry.lastSpeed * DECEL_FRACTION
		and entry.lastSpeed >= MIN_IMPACT_SPEED
		and now - entry.lastKickAt >= COOLDOWN
	then
		entry.pendingSpeed = entry.lastSpeed
		-- The direction it was travelling while it still had speed — by now it has
		-- already stopped, so this frame's velocity says nothing about the hit.
		entry.pendingDirection = if entry.lastVelocity.Magnitude > 1e-3
			then entry.lastVelocity.Unit
			else Vector3.new(0, -1, 0)
	end

	if speed > 0 then
		entry.lastVelocity = velocity
	end
	entry.lastSpeed = speed

	-- Damped spring, semi-implicit Euler. delta is clamped by the caller, or a
	-- frame hitch integrates the spring straight past its own limits.
	local accel = -STIFFNESS * entry.e - DAMPING * entry.ev
	entry.ev += accel * delta
	entry.e = math.clamp(entry.e + entry.ev * delta, -MAX_ELONGATION, MAX_ELONGATION)

	local stretch = 0
	if speed > MIN_IMPACT_SPEED and not hit then
		stretch = math.clamp(speed / FALL_FULL_SPEED, 0, 1) * FALL_STRETCH
		entry.axis = axisFor(entry, velocity.Unit)
	end

	local total = math.clamp(entry.e + stretch, -MAX_ELONGATION, MAX_ELONGATION)
	-- A settled tower is dozens of blocks sitting at rest; writing identity scales
	-- to all of them every frame is the one way this gets expensive.
	if math.abs(total) < 0.001 then
		if entry.dirty then
			write(entry, 0)
			entry.dirty = false
		end
		return
	end

	write(entry, total)
	entry.dirty = true
end

function TowerSquashController.Start()
	task.spawn(function()
		local arena = workspace:WaitForChild(Constants.ARENA_NAME)
		for _, child in arena:GetChildren() do
			if child:IsA("Model") then
				attach(child)
			end
		end
		arena.ChildAdded:Connect(function(child)
			if not child:IsA("Model") then
				return
			end
			-- One frame of grace: the server parents the model before it has finished
			-- parenting the body and its weld into it.
			task.defer(attach, child)
		end)
	end)

	RunService.RenderStepped:Connect(function(delta)
		-- Clamped so a hitch (or the first frame after a checkpoint demolition)
		-- can't hand the spring a delta it explodes on.
		local stepDelta = math.min(delta, 1 / 30)
		local now = os.clock()

		for model, entry in tracked do
			-- Destroyed by the storm, a checkpoint blast, a bomb, or a burn.
			if model.Parent == nil or entry.body.Parent == nil then
				tracked[model] = nil
				continue
			end
			step(entry, stepDelta, now)
		end
	end)
end

return TowerSquashController
