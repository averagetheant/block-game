-- The name plate that hangs off a piece: what it is, and what it does.
--
-- Server-built world UI rather than a React screen surface, for two reasons: it
-- has to sit *on the block*, and it has to be the same for everybody. A
-- BillboardGui parented to the piece replicates with it, so one instance covers
-- every player and the plate can't disagree between clients.
--
-- Anchored to an Attachment at the piece's bounding-box centre and pushed out by
-- a **world-space** offset, so the plate stays up and to the right no matter how
-- many quarter turns the holder has spun the piece through. (Adorning the root
-- cell instead would drag the plate around the piece as it rotates, because the
-- root cell moves within the model.)
--
-- The plate is a *piece* affordance, not a tower one: it's removed once the
-- block settles, or a fifty-block tower would be a wall of text.

local TweenService = game:GetService("TweenService")

local BlockLabel = {}

BlockLabel.NAME = "BlockLabel"

-- Roblox's Gotham. Minimal and legible at a distance, which the gem display font
-- (used by the screen UI) is not.
local FONT_FAMILY = "rbxasset://fonts/families/GothamSSm.json"
local WHITE = Color3.fromRGB(255, 255, 255)

-- Studs of clearance past the piece's bounding box. The plate is centred on this
-- point with its text left-aligned, so it reads as a tag hanging off the corner.
local OFFSET_X = 7
local OFFSET_Y = 2.5

local WIDTH = 240
local TITLE_HEIGHT = 22
local DESCRIPTION_HEIGHT = 18
local TITLE_SIZE = 19
local DESCRIPTION_SIZE = 15
-- The description is the quieter half of the plate.
local DESCRIPTION_TRANSPARENCY = 0.3
-- Thin dark outline: white text over a bright sky is otherwise unreadable, and
-- this is cheaper than putting a panel behind it.
local STROKE_TRANSPARENCY = 0.45

local FADE_SECONDS = 0.35

-- What the plate says. A typed piece leads with its type ("Bomb T-Shape"); a
-- plain one is just its silhouette ("T-Shape"). Types that bring their own model
-- have no shape to name, so they're only themselves ("Noob").
function BlockLabel.titleFor(typeName: string?, shapeName: string?): string
	if typeName == nil then
		-- Neither: nothing is in the air. The HUD renders this directly, so it
		-- gets a placeholder rather than a nil check at every call site.
		return if shapeName == nil then "—" else `{shapeName}-Shape`
	end
	if shapeName == nil then
		return typeName
	end
	return `{typeName} {shapeName}-Shape`
end

local function text(
	name: string,
	content: string,
	height: number,
	size: number,
	weight: Enum.FontWeight,
	transparency: number
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, height)
	label.Text = content
	label.TextColor3 = WHITE
	label.TextSize = size
	label.TextTransparency = transparency
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.FontFace = Font.new(FONT_FAMILY, weight, Enum.FontStyle.Normal)

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 1
	stroke.Transparency = STROKE_TRANSPARENCY
	stroke.Parent = label

	return label
end

-- `root` only has to be *a* part of the model — the attachment rides it, and the
-- offset is measured from the model's bounding box, not from the part.
function BlockLabel.attach(model: Model, root: BasePart, title: string, description: string?)
	local center, size = model:GetBoundingBox()

	local anchor = Instance.new("Attachment")
	anchor.Name = "BlockLabelAnchor"
	-- The attachment is fixed in the part's local space, so it tracks the piece
	-- through physics without anything having to update it per frame.
	anchor.CFrame = root.CFrame:ToObjectSpace(center)
	anchor.Parent = root

	local billboard = Instance.new("BillboardGui")
	billboard.Name = BlockLabel.NAME
	billboard.Adornee = anchor
	billboard.Size = UDim2.fromOffset(WIDTH, TITLE_HEIGHT + (if description then DESCRIPTION_HEIGHT else 0))
	billboard.StudsOffsetWorldSpace = Vector3.new(size.X / 2 + OFFSET_X, size.Y / 2 + OFFSET_Y, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 500
	billboard.ResetOnSpawn = false

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = billboard

	local titleLabel = text("Title", title, TITLE_HEIGHT, TITLE_SIZE, Enum.FontWeight.Bold, 0)
	titleLabel.LayoutOrder = 1
	titleLabel.Parent = billboard

	if description then
		local descriptionLabel = text(
			"Description",
			description,
			DESCRIPTION_HEIGHT,
			DESCRIPTION_SIZE,
			Enum.FontWeight.Light,
			DESCRIPTION_TRANSPARENCY
		)
		descriptionLabel.LayoutOrder = 2
		descriptionLabel.Parent = billboard
	end

	billboard.Parent = model
end

function BlockLabel.find(model: Model): BillboardGui?
	local billboard = model:FindFirstChild(BlockLabel.NAME)
	return if billboard and billboard:IsA("BillboardGui") then billboard else nil
end

-- Called when the block settles. Fades rather than blinking out, so a plate that
-- vanishes reads as the block being done rather than as a dropped instance.
function BlockLabel.dismiss(model: Model)
	local billboard = BlockLabel.find(model)
	if billboard == nil then
		return
	end
	-- Renaming first means a second dismiss (a block that settles, gets knocked
	-- loose and settles again) can't start a second tween on the same plate.
	billboard.Name = "BlockLabelFading"

	local info = TweenInfo.new(FADE_SECONDS)
	for _, label in billboard:GetChildren() do
		if not label:IsA("TextLabel") then
			continue
		end
		TweenService:Create(label, info, { TextTransparency = 1 }):Play()
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, info, { Transparency = 1 }):Play()
		end
	end

	task.delay(FADE_SECONDS, function()
		billboard:Destroy()
	end)
end

return BlockLabel
