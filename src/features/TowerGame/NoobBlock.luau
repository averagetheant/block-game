-- The Noob block: a piece that isn't a piece.
--
-- Most block types decorate a tetromino. This one replaces it — the holder aims
-- and drops a Noob, and once it lands it stops being cargo and starts being a
-- character: it wanders along the play plane and jumps at random until something
-- falls on it.
--
-- The rig is a **Studio asset** (`ReplicatedStorage.Assets.Noob`), so every
-- lookup here degrades to nil and TowerService quietly rolls an ordinary block
-- instead. A missing model should cost you the joke, not the turn.
--
-- Realm-neutral file, server-only in practice: the model it builds is server-
-- owned like every other piece, so its walk replicates for free and nobody has
-- to trust a client about where the Noob is.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)

local NoobBlock = {}

local TEMPLATE_NAME = "Noob"

local function template(): Model?
	local assets = ReplicatedStorage:FindFirstChild(Constants.ASSETS_FOLDER)
	local noob = if assets then assets:FindFirstChild(TEMPLATE_NAME) else nil
	return if noob and noob:IsA("Model") then noob :: Model else nil
end

function NoobBlock.setAnchored(model: Model, anchored: boolean)
	-- Descendants, not children: hats and accessories hang a Handle one level
	-- deeper, and an anchored hat on an unanchored rig floats where it was.
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = anchored
		end
	end
end

function NoobBlock.humanoidOf(instance: Instance?): Humanoid?
	local model = instance and instance:FindFirstAncestorOfClass("Model")
	return if model then model:FindFirstChildOfClass("Humanoid") else nil
end

-- Returns nil when the Studio asset is missing or isn't a rig, which is the
-- caller's cue to build an ordinary block instead.
function NoobBlock.build(): (Model?, BasePart?)
	local source = template()
	if source == nil then
		return nil, nil
	end

	local model = source:Clone()
	model.Name = "Piece_Noob"

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChildWhichIsA("BasePart")
	if humanoid == nil or root == nil or not root:IsA("BasePart") then
		model:Destroy()
		return nil, nil
	end

	-- Held pieces are anchored and steered by PivotTo; the rig only comes alive
	-- once it's landed.
	NoobBlock.setAnchored(model, true)
	humanoid.WalkSpeed = 0
	humanoid.AutoRotate = true

	-- Same reason the tetromino models have no PrimaryPart: with one set,
	-- PivotTo swings the model around that part instead of honouring WorldPivot,
	-- so a quarter turn would throw the Noob sideways rather than spin it.
	model.PrimaryPart = nil
	model.WorldPivot = model:GetBoundingBox()
	-- Tells TowerService's zone dressing to leave this model alone: studding a
	-- Noob over or handing it snow friction makes it a prop again.
	model:SetAttribute(Constants.RAW_MODEL_ATTRIBUTE, true)

	return model, root
end

-- Landed. From here the Noob drives itself until something lands on it, it walks
-- off the edge, or the tower under it is cleared.
function NoobBlock.activate(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		return
	end
	humanoid.WalkSpeed = Constants.NOOB_WALK_SPEED
	humanoid.JumpPower = Constants.NOOB_JUMP_POWER
	humanoid.UseJumpPower = true

	task.spawn(function()
		while model.Parent ~= nil and humanoid.Health > 0 do
			-- Only ever along X. The game is one Z slice, and a Noob that wandered
			-- out of it would be dragged back by the plane clamp every frame.
			local direction = math.random(-1, 1)
			humanoid:Move(Vector3.new(direction, 0, 0), false)
			if math.random() < Constants.NOOB_JUMP_CHANCE then
				humanoid.Jump = true
			end
			task.wait(Constants.NOOB_STEP_SECONDS * (0.6 + math.random()))
		end
	end)
end

-- Squashed. Ragdolls on the spot (BreakJointsOnDeath does the work) and clears
-- itself up a moment later.
function NoobBlock.kill(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		return
	end
	humanoid.Health = 0

	task.delay(Constants.NOOB_DESPAWN_SECONDS, function()
		model:Destroy()
	end)
end

return NoobBlock
