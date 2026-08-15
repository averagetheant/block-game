--!strict
-- A real T-block, spinning in a ViewportFrame. The art slot for a skin pack's
-- shop and inventory cards.
--
-- A flat icon can't show what a skin pack sells. The colour packs differ from
-- each other *only* by hue, and Neon differs from all of them only by material —
-- neither survives being redrawn as a 2D symbol, so the card shows the actual
-- thing instead. Same reason the reaction packs preview as their emoji.
--
-- The T is the shape most legible at a glance: four cells, no rotational
-- symmetry to make it read as a square, and it's the piece the game's own name
-- plates use as the default silhouette.
--
-- Built imperatively and spun on RenderStepped, because a ViewportFrame's
-- contents are Instances rather than React elements — there is nothing for React
-- to reconcile here beyond the frame itself.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage.Packages.React)
local Constants = require(script.Parent.Constants)

export type Props = {
	-- Drawn on every cell. The colour packs roll a shade per block in game; a
	-- card shows one so the tile is stable to look at.
	color: Color3,
	material: Enum.Material?,
	-- A skin that isn't solid (Needoh's glass) reads as the wrong material
	-- entirely when the card draws it opaque, so the tile carries it too.
	transparency: number?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
}

-- The T, in cell coordinates. Centred on the middle of the bar so the model
-- spins about itself rather than swinging around a corner cell.
local CELLS = {
	Vector3.new(-1, 0, 0),
	Vector3.new(0, 0, 0),
	Vector3.new(1, 0, 0),
	Vector3.new(0, 1, 0),
}

local CELL = 1
-- Far enough back to hold the whole piece with room around it.
local CAMERA_DISTANCE = 6.5
-- Tilted down and to the side, so the block reads as a solid rather than as a
-- flat cross seen head-on.
local CAMERA_ANGLE = CFrame.Angles(math.rad(-18), math.rad(28), 0)
local SPIN_SPEED = 0.6

return function(props: Props)
	local viewportRef = React.useRef(nil :: ViewportFrame?)
	local color = props.color
	local material = props.material or Enum.Material.SmoothPlastic
	local transparency = props.transparency or 0

	React.useEffect(function()
		local viewport = viewportRef.current
		if viewport == nil then
			return
		end

		local model = Instance.new("Model")
		for index, cell in CELLS do
			local part = Instance.new("Part")
			part.Name = `Cell{index}`
			part.Size = Vector3.one * CELL
			part.CFrame = CFrame.new(cell * CELL)
			part.Color = color
			part.Material = material
			part.Transparency = transparency
			part.Anchored = true
			part.CanCollide = false
			part.TopSurface = Enum.SurfaceType.Smooth
			part.BottomSurface = Enum.SurfaceType.Smooth
			part.Parent = model
		end
		model.Parent = viewport

		local camera = Instance.new("Camera")
		camera.FieldOfView = 40
		camera.Parent = viewport
		viewport.CurrentCamera = camera

		-- A ViewportFrame ignores world lighting, so the light has to come with
		-- it or every skin renders as the same flat silhouette.
		viewport.LightDirection = Vector3.new(-0.4, -1, -0.6)
		viewport.Ambient = Color3.fromRGB(150, 150, 160)
		viewport.LightColor = Color3.fromRGB(255, 255, 255)

		-- The camera never moves — the block spins instead, which keeps the
		-- lighting steady across the turn and costs one PivotTo a frame.
		camera.CFrame = CFrame.lookAt(
			(CAMERA_ANGLE * CFrame.new(0, 0, CAMERA_DISTANCE)).Position,
			Vector3.zero
		)

		local spin = 0
		local connection = RunService.RenderStepped:Connect(function(deltaTime)
			spin += deltaTime * SPIN_SPEED
			model:PivotTo(CFrame.Angles(0, spin, 0))
		end)

		return function()
			connection:Disconnect()
			model:Destroy()
			camera:Destroy()
		end
	end, { color, material, transparency } :: { any })

	return React.createElement("ViewportFrame", {
		ref = viewportRef,
		Size = props.size or UDim2.fromScale(1, 1),
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		LayoutOrder = props.layoutOrder,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	})
end
