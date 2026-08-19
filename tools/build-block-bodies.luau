-- Builds ReplicatedStorage.Assets.BlockBodies — the rounded shell every block is
-- seen as, one CSG union per tetromino shape.
--
-- NOT a Lune script: unlike everything else in this folder, this one is pasted
-- into the Roblox Studio **command bar in Edit mode**. What it makes is CSG, which
-- can't be authored in a text file and which Rojo doesn't sync — but an asset
-- built by hand once and never written down is one nobody can rebuild or retune,
-- so the construction lives here.
--
-- ------------------------------------------------------------ the geometry --
--
-- A rounded box is three inner slabs, eight corner spheres and twelve edge
-- cylinders, unioned: flat faces, rounded edges. Roblox has no rounded primitive.
--
-- The whole difficulty is making a *four-cell piece* look like one moulded shape
-- instead of four blocks touching. Two things do that, and both are needed —
-- either one alone still reads as segmented.
--
-- **1. Round the biggest rectangles, not the cells.** The shape is first cut into
-- as few axis-aligned rectangles as possible (greedy, largest first), and each
-- rectangle gets *one* rounded box. An I-piece and an O-piece come out as a single
-- rounded box with no internal geometry at all; T, L, J, S and Z come out as two.
-- Rounding each cell separately instead put a groove at every joint — three of
-- them on an I-piece, which is exactly what made it look like a row of cubes.
--
-- Where two rectangles do meet, the groove between them is filled by a short
-- rounded prism spanning the joint (`bridge`), so the silhouette runs straight
-- through and only the shape's true outer corners stay round.
--
-- **2. Smooth the shading.** `SmoothingAngle` defaults to 0, which is flat shading
-- — every facet of every rounded edge is lit as its own plane, so a smooth curve
-- reads as a stack of chamfers and each joint reads as a hard line. At 50 the
-- normals blend across anything meeting at less than that angle, which covers the
-- rounding and the joints while leaving the six real faces crisp.
--
-- Radius 0.7 on a 4-stud cell. Bigger starts eating the flat face the blocks are
-- read by; smaller stops reading as rounded at the camera's distance.
--
-- Each body carries two attributes the runtime needs:
--   * `CellOffset` — where the union's centre sits relative to cell (0,0). A
--     union's centre is its geometric centroid, which is neither the first cell
--     nor the middle of the piece, and differs per shape.
--   * `BaseSize` — its size before anything squashes it, so the squash has
--     something to scale *from*.
--
-- Re-running replaces the folder. Studio keeps none of it until you save.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local S = 4 -- Constants.BLOCK_SIZE
local R = 0.7 -- corner radius
local SMOOTHING = 50 -- degrees; 0 (the default) is flat shading

-- Mirrors Shapes.luau. Kept as literals rather than read from the module because
-- the command bar has no access to the Rojo-built tree before a sync — which
-- means this table is a second source of truth and has to be edited alongside the
-- first. `BlockBody` finds a union by `shape.name`, so a key here that disagrees
-- with `Shapes.luau` hands a piece somebody else's shell.
--
-- S and Z were swapped in both files at the same time; see the note in
-- `Shapes.luau` for which is which and why.
local SHAPES = {
	I = { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 3, 0 } },
	O = { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } },
	T = { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 1, 1 } },
	Z = { { 1, 0 }, { 2, 0 }, { 0, 1 }, { 1, 1 } },
	S = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 2, 1 } },
	J = { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 0, 1 } },
	L = { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 2, 1 } },
}

local scratch = Instance.new("Folder")
scratch.Parent = workspace

local function key(x: number, y: number): string
	return `{x},{y}`
end

-- Cut the shape into as few axis-aligned rectangles as possible: repeatedly take
-- the largest rectangle that fits entirely in what's left. Tetrominoes are four
-- cells, so brute force over every candidate is free.
local function rectangles(cells: { { number } }): { { x0: number, y0: number, x1: number, y1: number } }
	local left = {}
	for _, c in cells do
		left[key(c[1], c[2])] = true
	end

	local rects = {}
	while next(left) ~= nil do
		local best, bestArea = nil, 0
		for _, a in cells do
			for _, b in cells do
				local x0, x1 = math.min(a[1], b[1]), math.max(a[1], b[1])
				local y0, y1 = math.min(a[2], b[2]), math.max(a[2], b[2])
				local fits = true
				for x = x0, x1 do
					for y = y0, y1 do
						if not left[key(x, y)] then
							fits = false
							break
						end
					end
					if not fits then
						break
					end
				end
				local area = (x1 - x0 + 1) * (y1 - y0 + 1)
				if fits and area > bestArea then
					best, bestArea = { x0 = x0, y0 = y0, x1 = x1, y1 = y1 }, area
				end
			end
		end
		if best == nil then
			break
		end
		for x = best.x0, best.x1 do
			for y = best.y0, best.y1 do
				left[key(x, y)] = nil
			end
		end
		table.insert(rects, best)
	end
	return rects
end

local function box(size: Vector3, cf: CFrame): Part
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.Parent = scratch
	return p
end

local function ball(radius: number, cf: CFrame): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.one * (radius * 2)
	p.CFrame = cf
	p.Anchored = true
	p.Parent = scratch
	return p
end

local function cylinder(length: number, radius: number, cf: CFrame): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(length, radius * 2, radius * 2)
	p.CFrame = cf
	p.Anchored = true
	p.Parent = scratch
	return p
end

-- A rounded box of arbitrary size: the standard construction, emitted once per
-- rectangle rather than once per cell.
local function roundedBox(size: Vector3, centre: Vector3, parts: { Part })
	local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
	local at = CFrame.new(centre)

	table.insert(parts, box(Vector3.new(size.X, size.Y - 2 * R, size.Z - 2 * R), at))
	table.insert(parts, box(Vector3.new(size.X - 2 * R, size.Y, size.Z - 2 * R), at))
	table.insert(parts, box(Vector3.new(size.X - 2 * R, size.Y - 2 * R, size.Z), at))

	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				table.insert(parts, ball(R, at * CFrame.new(sx * (hx - R), sy * (hy - R), sz * (hz - R))))
			end
		end
	end

	local alongX = CFrame.Angles(0, 0, 0)
	local alongY = CFrame.Angles(0, 0, math.pi / 2)
	local alongZ = CFrame.Angles(0, math.pi / 2, 0)
	for _, sy in { -1, 1 } do
		for _, sz in { -1, 1 } do
			table.insert(parts, cylinder(size.X - 2 * R, R, at * CFrame.new(0, sy * (hy - R), sz * (hz - R)) * alongX))
		end
	end
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			table.insert(parts, cylinder(size.Y - 2 * R, R, at * CFrame.new(sx * (hx - R), 0, sz * (hz - R)) * alongY))
		end
	end
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			table.insert(parts, cylinder(size.Z - 2 * R, R, at * CFrame.new(sx * (hx - R), sy * (hy - R), 0) * alongZ))
		end
	end
end

-- The groove where two rectangles meet, filled with a short rounded prism of the
-- cell's own cross-section. 2R long, centred on the boundary — exactly the stretch
-- the two roundings pinch in over — so the silhouette runs straight through.
local function bridge(centre: Vector3, horizontal: boolean, parts: { Part })
	local at = CFrame.new(centre)
	local span = 2 * R
	local flat = S - 2 * R
	local half = S / 2 - R

	if horizontal then
		table.insert(parts, box(Vector3.new(span, S, flat), at))
		table.insert(parts, box(Vector3.new(span, flat, S), at))
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				table.insert(parts, cylinder(span, R, at * CFrame.new(0, sy * half, sz * half)))
			end
		end
	else
		table.insert(parts, box(Vector3.new(S, span, flat), at))
		table.insert(parts, box(Vector3.new(flat, span, S), at))
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				table.insert(
					parts,
					cylinder(span, R, at * CFrame.new(sx * half, 0, sz * half) * CFrame.Angles(0, 0, math.pi / 2))
				)
			end
		end
	end
end

local assets = ReplicatedStorage:FindFirstChild("Assets")
if assets == nil then
	assets = Instance.new("Folder")
	assets.Name = "Assets"
	assets.Parent = ReplicatedStorage
end

local existing = assets:FindFirstChild("BlockBodies")
if existing then
	existing:Destroy()
end
local bodies = Instance.new("Folder")
bodies.Name = "BlockBodies"
bodies.Parent = assets

local report = {}
for name, cells in SHAPES do
	local rects = rectangles(cells)

	-- which rectangle each cell ended up in, so a joint between two cells of the
	-- same rectangle is skipped: there is no groove there to fill.
	local rectOf = {}
	for index, r in rects do
		for x = r.x0, r.x1 do
			for y = r.y0, r.y1 do
				rectOf[key(x, y)] = index
			end
		end
	end

	local parts = {}
	for _, r in rects do
		local size = Vector3.new((r.x1 - r.x0 + 1) * S, (r.y1 - r.y0 + 1) * S, S)
		local centre = Vector3.new((r.x0 + r.x1) / 2 * S, (r.y0 + r.y1) / 2 * S, 0)
		roundedBox(size, centre, parts)
	end

	for _, c in cells do
		local x, y = c[1], c[2]
		local mine = rectOf[key(x, y)]
		local right = rectOf[key(x + 1, y)]
		if right ~= nil and right ~= mine then
			bridge(Vector3.new((x + 0.5) * S, y * S, 0), true, parts)
		end
		local up = rectOf[key(x, y + 1)]
		if up ~= nil and up ~= mine then
			bridge(Vector3.new(x * S, (y + 0.5) * S, 0), false, parts)
		end
	end

	local first = parts[1]
	local rest = {}
	for i = 2, #parts do
		table.insert(rest, parts[i])
	end
	local union = first:UnionAsync(rest)
	for _, p in parts do
		p:Destroy()
	end

	union.Name = name
	union.Anchored = true
	-- So a block's rolled colour shows: without it the union keeps the colours of
	-- the parts it was made from.
	union.UsePartColor = true
	union.CanCollide = false
	-- The landing preview casts straight down the play plane, and the body must not
	-- read as a surface a piece could land on — the cells it covers do that.
	union.CanQuery = false
	union.CanTouch = false
	-- The whole reason the squash may write Size: no mass, so no physics.
	union.Massless = true
	union.Material = Enum.Material.SmoothPlastic
	-- Flat shading is what made a smooth curve read as a stack of chamfers.
	union.SmoothingAngle = SMOOTHING
	union:SetAttribute("CellOffset", union.CFrame)
	union:SetAttribute("BaseSize", union.Size)
	union:SetAttribute("BlockBody", true)
	union.Parent = bodies

	table.insert(
		report,
		("%s: %d rect(s), size=%s tris=%d"):format(name, #rects, tostring(union.Size), union.TriangleCount)
	)
end

scratch:Destroy()
return table.concat(report, "\n")
