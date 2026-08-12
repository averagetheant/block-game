-- The seven tetrominoes, as grid-cell offsets in the play plane.
--
-- Cells are in *cell units*, not studs — TowerService multiplies by
-- Constants.BLOCK_SIZE when it builds the part model. X grows right, Y grows up.
-- Rotation isn't encoded here: a piece is a Model whose pivot sits at its
-- bounding-box center, so rotating is `PivotTo(pivot * CFrame.Angles(0, 0, ±90°))`
-- and the four orientations fall out of the physics engine for free.
--
-- `id` is what goes over the wire (uint8) and what the HUD looks up to name the
-- current piece, so ids must stay stable — append new shapes, don't renumber.

export type Shape = {
	id: number,
	name: string,
	color: Color3,
	cells: { Vector2 },
}

local Shapes = {}

Shapes.List = {
	{
		id = 1,
		name = "I",
		color = Color3.fromRGB(88, 209, 226),
		cells = { Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(2, 0), Vector2.new(3, 0) },
	},
	{
		id = 2,
		name = "O",
		color = Color3.fromRGB(240, 200, 74),
		cells = { Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) },
	},
	{
		id = 3,
		name = "T",
		color = Color3.fromRGB(178, 106, 224),
		cells = { Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(2, 0), Vector2.new(1, 1) },
	},
	{
		id = 4,
		name = "S",
		color = Color3.fromRGB(112, 214, 122),
		cells = { Vector2.new(1, 0), Vector2.new(2, 0), Vector2.new(0, 1), Vector2.new(1, 1) },
	},
	{
		id = 5,
		name = "Z",
		color = Color3.fromRGB(232, 96, 96),
		cells = { Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(1, 1), Vector2.new(2, 1) },
	},
	{
		id = 6,
		name = "J",
		color = Color3.fromRGB(92, 132, 232),
		cells = { Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(2, 0), Vector2.new(0, 1) },
	},
	{
		id = 7,
		name = "L",
		color = Color3.fromRGB(236, 150, 72),
		cells = { Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(2, 0), Vector2.new(2, 1) },
	},
} :: { Shape }

local byId: { [number]: Shape } = {}
for _, shape in Shapes.List do
	byId[shape.id] = shape
end

function Shapes.get(id: number): Shape?
	return byId[id]
end

-- Display name for a shape id; "—" for 0 / unknown so the HUD can render the
-- return value directly without a nil check.
function Shapes.nameOf(id: number?): string
	local shape = if id then byId[id] else nil
	return if shape then shape.name else "—"
end

function Shapes.random(): Shape
	return Shapes.List[math.random(1, #Shapes.List)]
end

return Shapes
