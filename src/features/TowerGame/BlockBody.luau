-- The rounded, glossy shell every block wears.
--
-- A piece is still four welded 4x4x4 cubes — that's the collision, the mass, and
-- everything TowerService measures. What changed is that those cubes are now
-- invisible, and the piece wears a single **body**: one CSG union of the whole
-- tetromino, corners rounded, edge profile running straight through the joints so
-- the silhouette reads as one moulded piece rather than four blocks stacked
-- against each other.
--
-- Why a separate visual at all, rather than rounding the cells themselves: a
-- rounded *collision* shape would change how the tower stacks — pieces would
-- settle into each other's corners and a flat course would stop being flat. The
-- game's feel is built on square cells. So the squares stay, and the roundness is
-- a coat over them.
--
-- The body is `CanCollide` false, `CanQuery` false and `Massless`, which is what
-- makes it safe to *resize* — the squash writes `Size` every frame, and on a part
-- with no collision and no mass that is invisible to the physics engine. Resizing
-- a cell instead would change its mass (breaking the Anvil and Feather densities),
-- change its collision, and corrupt `partTopY` -> `restingTopY` ->
-- `SPAWN_CLEARANCE`, which is how a piece ends up spawning inside the tower.
--
-- The bodies are **Studio assets** (`ReplicatedStorage.Assets.BlockBodies.<shape>`,
-- built by tools/build-block-bodies), because CSG can't be authored in a text
-- file. Every lookup degrades to nil and the piece falls back to plain visible
-- cubes — the game it was before this — rather than to nothing at all.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)
local Shapes = require(ReplicatedStorage.Features.TowerGame.Shapes)

local BlockBody = {}

local FOLDER_NAME = "BlockBodies"
local BODY_NAME = "Body"
local WELD_NAME = "BodyWeld"

local function folder(): Instance?
	local assets = ReplicatedStorage:FindFirstChild(Constants.ASSETS_FOLDER)
	return if assets then assets:FindFirstChild(FOLDER_NAME) else nil
end

local function template(shape: Shapes.Shape): BasePart?
	local bodies = folder()
	local body = if bodies then bodies:FindFirstChild(shape.name) else nil
	return if body and body:IsA("BasePart") then body :: BasePart else nil
end

function BlockBody.available(shape: Shapes.Shape?): boolean
	if shape == nil then
		return false
	end
	return template(shape) ~= nil
end

-- True for the visible shell of a block. The guard `modelParts` uses: the body is
-- a BasePart descendant of the piece like any cell, but it is not a cell — it
-- carries no mass, answers no raycast, and is a stud wider than the cube it
-- covers whenever the squash has hold of it.
function BlockBody.isBody(part: BasePart): boolean
	return part:GetAttribute(Constants.BODY_ATTRIBUTE) == true
end

function BlockBody.of(model: Model): BasePart?
	local body = model:FindFirstChild(BODY_NAME)
	return if body and body:IsA("BasePart") then body :: BasePart else nil
end

-- Dress a freshly-built piece. Returns the body, or nil when the asset is missing
-- — in which case the caller leaves the cubes visible and the game looks the way
-- it did before there were bodies.
--
-- `root` is the piece's first cell, which the body is welded to. A legacy `Weld`
-- rather than a `WeldConstraint`, because `C0` is what the squash shifts: a block
-- landing has to flatten *onto* the thing it hit, and a body that only scaled
-- about its own centre would lift its bottom face off the surface by half of
-- whatever it squashed.
function BlockBody.attach(
	model: Model,
	root: BasePart,
	shape: Shapes.Shape,
	color: Color3,
	material: Enum.Material,
	transparency: number
): BasePart?
	local source = template(shape)
	if source == nil then
		return nil
	end

	local body = source:Clone()
	body.Name = BODY_NAME
	body.Color = color
	body.Material = material
	body.Transparency = transparency
	body.Anchored = root.Anchored
	body:SetAttribute(Constants.BODY_ATTRIBUTE, true)

	-- The union's own centre is its geometric centroid, which is neither the first
	-- cell nor the piece's middle and differs per shape — so where it sits relative
	-- to cell (0,0) was measured when the asset was built and travels with it.
	--
	-- `buildPiece` lays its cells out in the piece's own frame — cell (n) at
	-- (n.X * BLOCK_SIZE, n.Y * BLOCK_SIZE, PLANE_Z) — and only pivots the finished
	-- model afterwards, so the offset is applied against that untransformed layout
	-- and the weld carries the body through every move and quarter turn after it.
	local offset = source:GetAttribute("CellOffset") :: CFrame
	body.CFrame = CFrame.new(0, 0, Constants.PLANE_Z) * offset
	body.Parent = model

	local weld = Instance.new("Weld")
	weld.Name = WELD_NAME
	weld.Part0 = root
	weld.Part1 = body
	weld.C0 = root.CFrame:ToObjectSpace(body.CFrame)
	weld.Parent = body

	return body
end

-- What the body's weld rests at, so the squash has something to return to. Read
-- once when a block starts wobbling rather than stored per block: the piece may
-- have been rotated any number of quarter turns since it was built.
function BlockBody.restOf(body: BasePart): (CFrame, Vector3)
	local weld = body:FindFirstChild(WELD_NAME) :: Weld?
	local base = body:GetAttribute("BaseSize") :: Vector3
	return (if weld then weld.C0 else CFrame.new()), base or body.Size
end

function BlockBody.weldOf(body: BasePart): Weld?
	local weld = body:FindFirstChild(WELD_NAME)
	return if weld and weld:IsA("Weld") then weld :: Weld else nil
end

return BlockBody
