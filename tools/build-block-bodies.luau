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
-- The part that matters is what happens **between cells**. Round each cell
-- separately and a tetromino comes out looking like four blocks bolted together,
-- with a groove at every joint. So a cell with a neighbour on some side drops the
-- rounding on that side and grows a slab out to meet it, and the edge cylinders
-- running past a joint are extended through it. The result is one moulded piece
-- whose silhouette is rounded only at the shape's true outside corners — which is
-- what the reference art does.
--
-- Radius 0.7 on a 4-stud cell. Bigger starts eating the flat face the blocks are
-- read by; smaller stops reading as rounded at all at the camera's distance.
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

-- Mirrors Shapes.luau. Kept as literals rather than read from the module because
-- the command bar has no access to the Rojo-built tree before a sync.
local SHAPES = {
	I = { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 3, 0 } },
	O = { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } },
	T = { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 1, 1 } },
	S = { { 1, 0 }, { 2, 0 }, { 0, 1 }, { 1, 1 } },
	Z = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 2, 1 } },
	J = { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 0, 1 } },
	L = { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 2, 1 } },
}

local scratch = Instance.new("Folder")
scratch.Parent = workspace

local function cellParts(cf: CFrame, occupied: { [string]: boolean }, cx: number, cy: number): { BasePart }
	local parts = {}
	local inner = S - 2 * R

	local function box(size: Vector3, offset: Vector3?)
		local p = Instance.new("Part")
		p.Size = size
		p.CFrame = cf * CFrame.new(offset or Vector3.zero)
		p.Anchored = true
		p.Parent = scratch
		table.insert(parts, p)
	end

	local function cyl(size: Vector3, offset: Vector3, rot: CFrame)
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Cylinder
		p.Size = size
		p.CFrame = cf * CFrame.new(offset) * rot
		p.Anchored = true
		p.Parent = scratch
		table.insert(parts, p)
	end

	local left = occupied[`{cx - 1},{cy}`] ~= nil
	local right = occupied[`{cx + 1},{cy}`] ~= nil
	local down = occupied[`{cx},{cy - 1}`] ~= nil
	local up = occupied[`{cx},{cy + 1}`] ~= nil

	box(Vector3.new(S, inner, inner))
	box(Vector3.new(inner, S, inner))
	box(Vector3.new(inner, inner, S))
	-- Fill the notch toward each neighbour: a full slab reaching half a cell out,
	-- which that neighbour's own slab meets in the middle.
	if left then
		box(Vector3.new(S / 2, S, inner), Vector3.new(-S / 4, 0, 0))
	end
	if right then
		box(Vector3.new(S / 2, S, inner), Vector3.new(S / 4, 0, 0))
	end
	if down then
		box(Vector3.new(S, S / 2, inner), Vector3.new(0, -S / 4, 0))
	end
	if up then
		box(Vector3.new(S, S / 2, inner), Vector3.new(0, S / 4, 0))
	end

	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			for _, z in { -1, 1 } do
				local p = Instance.new("Part")
				p.Shape = Enum.PartType.Ball
				p.Size = Vector3.one * (R * 2)
				p.CFrame = cf * CFrame.new(x * (S / 2 - R), y * (S / 2 - R), z * (S / 2 - R))
				p.Anchored = true
				p.Parent = scratch
				table.insert(parts, p)
			end
		end
	end

	-- Edge cylinders, stretched through any joint so the rounded profile runs
	-- unbroken down the length of a long piece.
	local xLen = S - (if left then 0 else R) - (if right then 0 else R)
	local xShift = ((if left then R else 0) - (if right then R else 0)) / 2
	for _, y in { -1, 1 } do
		for _, z in { -1, 1 } do
			cyl(
				Vector3.new(xLen, R * 2, R * 2),
				Vector3.new(xShift, y * (S / 2 - R), z * (S / 2 - R)),
				CFrame.Angles(0, 0, 0)
			)
		end
	end
	local yLen = S - (if down then 0 else R) - (if up then 0 else R)
	local yShift = ((if down then R else 0) - (if up then R else 0)) / 2
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			cyl(
				Vector3.new(yLen, R * 2, R * 2),
				Vector3.new(x * (S / 2 - R), yShift, z * (S / 2 - R)),
				CFrame.Angles(0, 0, math.pi / 2)
			)
		end
	end
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			cyl(
				Vector3.new(S - 2 * R, R * 2, R * 2),
				Vector3.new(x * (S / 2 - R), y * (S / 2 - R), 0),
				CFrame.Angles(0, math.pi / 2, 0)
			)
		end
	end
	return parts
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
	local occupied = {}
	for _, c in cells do
		occupied[`{c[1]},{c[2]}`] = true
	end

	local parts = {}
	for _, c in cells do
		-- Built in the piece's own cell frame — cell (0,0) at the origin — exactly
		-- as buildPiece lays its cubes out, so the offset below is the only thing
		-- the runtime needs to seat it.
		for _, p in cellParts(CFrame.new(c[1] * S, c[2] * S, 0), occupied, c[1], c[2]) do
			table.insert(parts, p)
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
	union:SetAttribute("CellOffset", union.CFrame)
	union:SetAttribute("BaseSize", union.Size)
	union:SetAttribute("BlockBody", true)
	union.Parent = bodies

	table.insert(report, ("%s: size=%s offset=%s tris=%d"):format(
		name,
		tostring(union.Size),
		tostring(union.CFrame.Position),
		union.TriangleCount
	))
end

scratch:Destroy()
return table.concat(report, "\n")
