--!strict
-- Draws a bolt of lightning that looks like one.
--
-- The shape is **midpoint displacement**: start with a straight line from A to B,
-- split every segment in half and shove the new middle sideways, then do it
-- again with half the shove. Four passes turns two points into sixteen segments
-- that wander the way a real discharge does — the path a spark actually takes is
-- a random walk through the air, and this is the cheap way to draw one.
--
-- Branches come off the same walk: a node may fork, and the fork is a shorter,
-- thinner bolt built by the same function at an angle to its parent. Forks don't
-- fork again — a fractal that recurses to the leaves is a tree, and lightning is
-- a bolt with a few branches off it.
--
-- Purely visual and purely local: anchored, collisionless, unqueryable Neon that
-- fades and deletes itself. Nothing here is replicated and nothing reads it back,
-- so a client that skipped every bolt would play the same game — which is what
-- lets the background storm throw them around by the dozen.
--
-- Client-realm because only clients draw. Both callers are client files: the
-- storm's background VFX (`TowerStormController`) and the Stormy zone's own
-- strike (`TowerZoneController`).

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)

local LightningBolt = {}

export type Options = {
	from: Vector3,
	to: Vector3,
	-- Trunk width in studs. Branches take a fraction of it.
	width: number,
	color: Color3,
	-- Where the parts go. The caller's business, so a bolt can be dropped into a
	-- folder it sweeps rather than loose in the workspace.
	parent: Instance,
	-- Overrides for the shape, all defaulted from Constants. The background storm
	-- leaves them alone; a caller drawing a small, close bolt wants fewer passes.
	passes: number?,
	jitter: number?,
	branchChance: number?,
	holdSeconds: number?,
	fadeSeconds: number?,
}

local function randomInRange(range: { number }): number
	return range[1] + math.random() * (range[2] - range[1])
end

-- Any unit vector at right angles to `direction`.
--
-- Built by crossing with whichever world axis the direction is *least* aligned
-- to, because crossing two nearly-parallel vectors gives something tiny and
-- normalising it amplifies floating-point noise into a random direction — which
-- for a bolt falling straight down (the common case here) would be every
-- segment's jitter pointing somewhere different for no reason.
local function anyPerpendicular(direction: Vector3): Vector3
	local axis = if math.abs(direction.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis
	return direction:Cross(axis).Unit
end

-- One pass of midpoint displacement over a path.
local function displace(points: { Vector3 }, amount: number): { Vector3 }
	local out = { points[1] }
	for index = 1, #points - 1 do
		local a, b = points[index], points[index + 1]
		local middle = (a + b) / 2
		local direction = (b - a)
		local length = direction.Magnitude
		if length > 0 then
			local perpendicular = anyPerpendicular(direction.Unit)
			-- Rolled about the segment's own axis, so the wander isn't confined to
			-- one plane — a bolt that only ever kinked left and right would read as
			-- a paper cut-out from the side the camera happens to be on.
			local spin = CFrame.fromAxisAngle(direction.Unit, math.random() * math.pi * 2)
			local offset = spin * perpendicular
			middle += offset * amount * (math.random() * 2 - 1)
		end
		table.insert(out, middle)
		table.insert(out, b)
	end
	return out
end

-- The wandering path from `from` to `to`.
local function pathFor(from: Vector3, to: Vector3, passes: number, jitter: number): { Vector3 }
	local points = { from, to }
	local amount = (to - from).Magnitude * jitter
	for _ = 1, passes do
		points = displace(points, amount)
		amount /= 2
	end
	return points
end

-- One segment, drawn as a thin Neon box lying along its own Z axis. A box rather
-- than a cylinder because a bolt is never seen end-on and a box is the cheaper
-- part; Neon because the whole point is that it's the brightest thing on screen
-- for a tenth of a second.
local function drawSegment(a: Vector3, b: Vector3, width: number, color: Color3, parent: Instance): BasePart?
	local delta = b - a
	local length = delta.Magnitude
	if length <= 0 then
		return nil
	end

	local part = Instance.new("Part")
	part.Name = "LightningSegment"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Size = Vector3.new(width, width, length)
	-- `lookAt` puts the part's Z axis along the direction it's looking, which is
	-- exactly the axis `Size.Z` runs down — so the box spans the segment with no
	-- second rotation to get wrong.
	part.CFrame = CFrame.lookAt((a + b) / 2, b)
	part.Parent = parent
	return part
end

-- Draw one path, and possibly branches off it. `depth` stops forks forking.
local function drawPath(
	points: { Vector3 },
	width: number,
	color: Color3,
	parent: Instance,
	options: Options,
	depth: number,
	parts: { BasePart }
)
	local branchChance = options.branchChance or Constants.BOLT_BRANCH_CHANCE
	local passes = options.passes or Constants.BOLT_PASSES
	local jitter = options.jitter or Constants.BOLT_JITTER

	for index = 1, #points - 1 do
		local a, b = points[index], points[index + 1]
		local part = drawSegment(a, b, width, color, parent)
		if part then
			table.insert(parts, part)
		end

		-- Forks come off a node, heading roughly on but leaning away, and they
		-- never reach as far as the trunk they left. The last node is skipped:
		-- a branch from the very end is a bolt that hit the ground and carried on.
		if depth > 0 or index >= #points - 1 or math.random() > branchChance then
			continue
		end

		local remaining = points[#points] - b
		local heading = if remaining.Magnitude > 0 then remaining.Unit else Vector3.yAxis
		local lean = math.rad(randomInRange(Constants.BOLT_BRANCH_SPREAD)) * (if math.random() < 0.5 then -1 else 1)
		local axis = anyPerpendicular(heading)
		local direction = CFrame.fromAxisAngle(axis, lean) * heading
		local length = remaining.Magnitude * randomInRange(Constants.BOLT_BRANCH_LENGTH)

		drawPath(
			-- One pass fewer: a branch is shorter, so the same pass count would
			-- give it finer kinks than the trunk and read as a different material.
			pathFor(b, b + direction * length, math.max(passes - 1, 1), jitter),
			width * Constants.BOLT_BRANCH_WIDTH,
			color,
			parent,
			options,
			depth + 1,
			parts
		)
	end
end

-- Strike, once. Returns nothing — the bolt owns its own lifetime.
function LightningBolt.strike(options: Options)
	local parts: { BasePart } = {}
	drawPath(
		pathFor(
			options.from,
			options.to,
			options.passes or Constants.BOLT_PASSES,
			options.jitter or Constants.BOLT_JITTER
		),
		options.width,
		options.color,
		options.parent,
		options,
		0,
		parts
	)

	-- Held at full brightness, *then* faded. A bolt that started fading on the
	-- frame it appeared would read as a light coming on; the hold is what makes it
	-- a flash.
	local hold = options.holdSeconds or Constants.BOLT_HOLD_SECONDS
	local fade = options.fadeSeconds or Constants.BOLT_FADE_SECONDS
	local info = TweenInfo.new(fade, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, hold)
	for _, part in parts do
		TweenService:Create(part, info, { Transparency = 1 }):Play()
		-- The tween is the animation and this is the net: a client that loses the
		-- tween (a hot reload mid-flash) still gets its parts collected.
		Debris:AddItem(part, hold + fade + 0.1)
	end
end

return LightningBolt
