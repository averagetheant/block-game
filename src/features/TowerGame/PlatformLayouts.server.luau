--!strict
-- The ground a run is built on, as a Studio asset rather than a constant.
--
-- The game has always stood on one 48-wide slab: `Constants.PLATFORM_SIZE`, used
-- for the base and for every checkpoint floor above it. That slab is a number in
-- a file, so the only ground the game could ever have was the one shape. This
-- file makes the ground a *model* — one Model per layout under
-- `ServerStorage.TowerPlatformLayouts` — so a floor can be two slabs with a gap
-- down the middle, three narrow columns, or a high centre between two low wings,
-- and every one of those is a different question to answer with a tetromino.
--
-- Why this needed almost no new rules: a floor was already a *list* of parts.
-- `platforms: { BasePart }` has held the checkpoint slabs since there was more
-- than one floor, and every consumer of it is already per-part and X-aware —
-- `restingTopY` picks the highest slab whose column contains x, `measureLane`
-- takes the max top, `blastPlatformsBelow` throws each one individually. A gap
-- is therefore already "no slab answers for this column", and a piece dropped
-- into one already falls past and is swept. So this file only has to *choose* a
-- layout and *stamp it out*; nothing downstream had to learn what a layout is.
--
-- Server-only (`.server.luau`) because the layouts live in ServerStorage: the
-- client never needs them. It reads the one number it cares about — the
-- scoreline — off the arena's `BaseTopY` attribute, exactly as before.
--
-- The whole thing is optional. A place with no layouts folder, or no layout
-- eligible for the floor being built, gets the generated slab it always got —
-- which is what keeps Boil bootable in an empty place.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)

export type Layout = {
	-- The Model's name, which is the layout's id.
	name: string,
	model: Model,
	-- Relative odds against the other eligible layouts. 1 is ordinary.
	weight: number,
	-- Earliest floor this may be built on. 0 is the base, 1 the first checkpoint.
	-- This is the difficulty dial: it keeps the clever ground away from the
	-- opening minute, so a run starts on something a new player can read.
	minCheckpoint: number,
	roles: { [string]: boolean },
}

local PlatformLayouts = {}

-- Read once and kept. The folder is authored in Studio and never changes while
-- the server is up, and re-walking it per checkpoint would buy nothing.
local cache: { Layout }? = nil

local function parseRoles(raw: unknown): { [string]: boolean }
	local roles = {}
	if typeof(raw) ~= "string" then
		-- No attribute means "wherever ground is wanted", which is the answer that
		-- makes a freshly duplicated layout work without being configured first.
		return { base = true, checkpoint = true }
	end
	for role in string.gmatch(raw :: string, "[^,%s]+") do
		roles[string.lower(role)] = true
	end
	return roles
end

local function numberAttribute(model: Model, name: string, fallback: number): number
	local value = model:GetAttribute(name)
	return if typeof(value) == "number" then value else fallback
end

-- A layout is only usable if it has slabs and they're on the play plane. Both
-- failures are silent in the world — a slab at z = 40 is a slab no piece can
-- ever touch — so they're worth a warning at load rather than a mystery later.
local function slabsOf(model: Model): { BasePart }?
	local slabs = {}
	for _, child in model:GetChildren() do
		if not child:IsA("BasePart") then
			continue
		end
		if child.Position.Z ~= Constants.PLANE_Z then
			warn(`[TowerGame] Platform layout "{model.Name}" has a slab off the play plane ({child.Name}); ignoring the layout.`)
			return nil
		end
		table.insert(slabs, child)
	end
	if #slabs == 0 then
		warn(`[TowerGame] Platform layout "{model.Name}" has no BaseParts; ignoring it.`)
		return nil
	end
	return slabs
end

local function read(): { Layout }
	if cache then
		return cache
	end

	local layouts: { Layout } = {}
	local folder = ServerStorage:FindFirstChild(Constants.PLATFORM_LAYOUTS_FOLDER)
	if folder then
		for _, model in folder:GetChildren() do
			if not model:IsA("Model") then
				continue
			end
			if slabsOf(model) == nil then
				continue
			end
			table.insert(layouts, {
				name = model.Name,
				model = model,
				weight = math.max(numberAttribute(model, "Weight", 1), 0),
				minCheckpoint = numberAttribute(model, "MinCheckpoint", 0),
				roles = parseRoles(model:GetAttribute("Roles")),
			})
		end
	end

	cache = layouts
	return layouts
end

-- A layout for this floor, or nil to fall back to the generated slab.
--
-- `checkpoint` is the floor number being built: 0 for the base, 1 for the first
-- checkpoint above it. Weighted rather than uniform so the plain slab can stay
-- the common case — a run where every floor is a twist is a run with no baseline
-- to be a twist against.
function PlatformLayouts.pick(role: string, checkpoint: number): Layout?
	local eligible = {}
	local total = 0
	for _, layout in read() do
		if not layout.roles[role] or checkpoint < layout.minCheckpoint or layout.weight <= 0 then
			continue
		end
		table.insert(eligible, layout)
		total += layout.weight
	end
	if total <= 0 then
		return nil
	end

	local roll = math.random() * total
	for _, layout in eligible do
		roll -= layout.weight
		if roll <= 0 then
			return layout
		end
	end
	return eligible[#eligible]
end

-- Stamp a layout out at `floorY` and hand back its slabs.
--
-- The Model is a mould, not the thing itself: it's cloned, pivoted so the
-- author's pivot lands on `floorY`, and then **flattened** — the slabs are
-- reparented to `parent` and the empty Model destroyed. Flattening matters for
-- two reasons. The arena's children are walked for held pieces
-- (`TowerAimController.findOwnPiece` looks for a Model stamped with a user id),
-- so leaving a Model there puts ground in a lookup that should only ever find
-- pieces; and `platforms` is a flat list of BaseParts that every measurement
-- already iterates, so slabs standing loose need no special case anywhere.
--
-- The pivot is the contract with the author: it's the scoreline, so a slab above
-- it is a wall and a slab below it is a hole to climb out of. See the README in
-- the layouts folder.
function PlatformLayouts.build(layout: Layout, floorY: number, parent: Instance, name: string): { BasePart }
	local clone = layout.model:Clone()
	clone:PivotTo(CFrame.new(0, floorY, Constants.PLANE_Z))

	local slabs = {}
	for _, child in clone:GetChildren() do
		if not child:IsA("BasePart") then
			continue
		end
		-- Named for the floor they are rather than for the layout they came from:
		-- an explorer full of "SlabLeft" tells you nothing about which floor blew
		-- up, and the layout's own name is on the attribute below.
		child.Name = `{name}_{child.Name}`
		child:SetAttribute("Layout", layout.name)
		-- Authored anchored, but an un-anchored slab is a floor that falls out
		-- from under the run — too expensive a mistake to leave to the author.
		child.Anchored = true
		-- Same argument, and the one that actually bit. A Studio part ships with
		-- stock plastic physics — friction 0.3, elasticity 0.5 — so an authored
		-- floor was *bouncy and slippery*: blocks landed on the base, bounced, and
		-- slid straight off it. Only the generated base ever got the game's own
		-- numbers, because that's the one path that built a part rather than
		-- adopting one.
		--
		-- Checkpoint slabs were never affected: `playInSlab` sets this again on
		-- every one of them a moment later. The base has no such second pass, which
		-- is exactly why the bug was the *baseplate* and nothing else.
		child.CustomPhysicalProperties = Constants.FLOOR_PHYSICS
		child.Parent = parent
		table.insert(slabs, child)
	end

	clone:Destroy()
	return slabs
end

return PlatformLayouts
