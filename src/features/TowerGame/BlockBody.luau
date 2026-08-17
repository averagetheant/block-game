-- The rounded, glossy shell every block is seen as.
--
-- A piece on the server is four welded 4x4x4 cubes, and that never changes: the
-- cubes collide, carry the mass, and every measurement TowerService makes lands
-- on them. They are square on purpose — a rounded collision shape settles into
-- its neighbours' corners and a flat course stops being flat.
--
-- The **body** is one CSG union of the whole tetromino, corners rounded and the
-- edge profile running straight through the joints between cells, so a piece
-- reads as one moulded shape rather than four blocks bolted together. It is built
-- by each client over the cubes (see TowerBodyController) and it renders instead
-- of them.
--
-- ------------------------------------------------ why the client builds it --
--
-- The body was made on the server first, welded onto the piece, and replicated
-- like anything else. It measured perfectly on the client — right Size, right
-- TriangleCount, mesh present — and drew as a tiny cube anyway. A union the
-- client clones out of its own ReplicatedStorage draws correctly, which is what
-- the aim preview has always done and why the preview looked right while the
-- dropped block didn't.
--
-- So the body is built where it renders. That also makes it free: no extra parts
-- replicate, the server has no opinion about it, and a client that can't build
-- one simply sees the visible cubes — the game as it was before bodies existed.
-- Same shape as the night lights in TowerZoneController.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)
local Shapes = require(ReplicatedStorage.Features.TowerGame.Shapes)

local BlockBody = {}

local FOLDER_NAME = "BlockBodies"

BlockBody.NAME = "Body"

local function folder(): Instance?
	local assets = ReplicatedStorage:FindFirstChild(Constants.ASSETS_FOLDER)
	return if assets then assets:FindFirstChild(FOLDER_NAME) else nil
end

local function template(shape: Shapes.Shape): BasePart?
	local bodies = folder()
	local body = if bodies then bodies:FindFirstChild(shape.name) else nil
	return if body and body:IsA("BasePart") then body :: BasePart else nil
end

-- The shape a piece was built from, read off the attribute the server stamps. Nil
-- for anything that isn't a tetromino — a Noob rig brings its own model and wears
-- no body.
function BlockBody.shapeOf(model: Model): Shapes.Shape?
	local id = model:GetAttribute(Constants.SHAPE_ATTRIBUTE)
	return if typeof(id) == "number" then Shapes.get(id) else nil
end

-- Build the body for a piece and park it in `parent`.
--
-- Deliberately **not** parented into the piece itself and never welded to it.
-- Welding a locally-created part onto a server-owned assembly puts a local
-- instance into the physics engine's idea of that assembly, and the body is meant
-- to be furniture — it has no mass, no collision, and nothing may depend on it.
-- The controller drives its CFrame from the piece's root cell every frame
-- instead, which also gives the squash somewhere to put its offset.
--
-- Returns the body and the fixed offset from the piece's root cell to the body's
-- rest position, in the root cell's own frame — so it survives every quarter turn
-- the piece takes.
function BlockBody.build(model: Model, root: BasePart, parent: Instance): (BasePart?, CFrame?)
	local shape = BlockBody.shapeOf(model)
	if shape == nil then
		return nil, nil
	end
	local source = template(shape)
	if source == nil then
		return nil, nil
	end

	local body = source:Clone()
	body.Name = BlockBody.NAME
	-- Never simulated: it's driven by hand from the cells it covers.
	body.Anchored = true
	body.CanCollide = false
	body.CanQuery = false
	body.CanTouch = false
	body.Massless = true
	body:SetAttribute(Constants.BODY_ATTRIBUTE, true)

	-- Where the union's centre sits relative to cell (0,0), measured when the asset
	-- was built: a union's centre is its geometric centroid, which is neither the
	-- first cell nor the middle of the piece and differs per shape.
	local cellOffset = source:GetAttribute("CellOffset") :: CFrame
	local first = shape.cells[1]
	local rootAt = Vector3.new(first.X * Constants.BLOCK_SIZE, first.Y * Constants.BLOCK_SIZE, 0)
	-- Both are pure translations in the piece's build frame, so the difference is
	-- the offset from the root cell to the body — and because it's expressed in the
	-- root's frame, rotating the piece rotates the body with it for free.
	local offset = CFrame.new(cellOffset.Position - rootAt)

	body.CFrame = root.CFrame * offset
	body.Parent = parent
	return body, offset
end

function BlockBody.baseSizeOf(body: BasePart): Vector3
	local base = body:GetAttribute("BaseSize")
	return if typeof(base) == "Vector3" then base :: Vector3 else body.Size
end

return BlockBody
