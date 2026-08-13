-- Paints the tower in whatever skin pack the local player has equipped.
--
-- Local only, and that's the point. The tower is shared — one stack, everyone's
-- — so a cosmetic one player bought must not change what the room sees. Writing
-- Material on a replicated part from the client changes it on this screen and
-- nowhere else, which is exactly the reach a bought skin should have.
--
-- It re-asserts on a slow sweep rather than once, because the server owns block
-- materials: it dresses every block when a piece spawns and re-dresses the whole
-- tower on every zone change (Retro turns the stack into grey studded bricks).
-- Each of those replicates down and stomps the override, so the override has to
-- keep putting itself back. Overriding *zone* materials is the product — see
-- SkinPacks.luau.
--
-- The sweep only runs while a material pack is equipped. Unequipped, this
-- controller costs one signal connection and nothing else.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)
local SkinPacks = require(ReplicatedStorage.Features.TowerGame.SkinPacks)
local Zones = require(ReplicatedStorage.Features.TowerGame.Zones)

-- Client-realm siblings.
local StoreController = require(script.Parent.Parent.Store.StoreController)
local PlayerDataController = require(script.Parent.Parent.PlayerData.PlayerDataController)
local TowerController = require(script.Parent.TowerController)

local TowerSkinController = {}

-- After the controllers whose state it reads.
TowerSkinController.Priority = 30

-- The material each part had before the override first touched it. Weak keys so
-- a destroyed block doesn't keep an entry alive — blocks are created and
-- destroyed constantly here.
local original: { [BasePart]: Enum.Material } = setmetatable({}, { __mode = "k" }) :: any

local active: SkinPacks.SkinPack? = nil

-- Every part of a *piece*. Pieces are Models under the arena; the base and the
-- checkpoint platforms are loose BaseParts, and re-skinning the floor the tower
-- stands on isn't what anyone bought.
local function pieceParts(): { BasePart }
	local arena = workspace:FindFirstChild(Constants.ARENA_NAME)
	if arena == nil then
		return {}
	end

	local found: { BasePart } = {}
	for _, model in arena:GetChildren() do
		if not model:IsA("Model") then
			continue
		end
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				table.insert(found, descendant)
			end
		end
	end
	return found
end

local function applyTo(parts: { BasePart }, material: Enum.Material)
	for _, part in parts do
		if original[part] == nil then
			original[part] = part.Material
		end
		if part.Material ~= material then
			part.Material = material
		end
	end
end

-- Put back what the server would be showing. For every zone but Retro that's
-- the material the block spawned with; Retro is the one that overrides it, so
-- it's the one case worth reconstructing rather than restoring.
local function restore()
	local retro = Zones.get(TowerController.GetData().zoneId).kind == "retro"
	for part, material in original do
		if part.Parent == nil then
			continue
		end
		part.Material = if retro then Enum.Material.Plastic else material
	end
	table.clear(original :: any)
end

local function equippedPack(): SkinPacks.SkinPack?
	return SkinPacks.get(StoreController.equipped(SkinPacks.KIND))
end

local function refresh()
	local pack = equippedPack()
	if pack == active then
		return
	end

	-- Anything the outgoing pack painted goes back first; otherwise the next
	-- pack's `original` would record *its* material as the block's own.
	restore()
	active = pack
	if pack ~= nil then
		applyTo(pieceParts(), pack.material)
	end
end

function TowerSkinController.Start()
	if not Constants.Presentations.skins then
		return
	end

	PlayerDataController.DataChanged:Connect(refresh)
	refresh()

	-- The sweep. Blocks spawn constantly and the server re-dresses the whole
	-- tower on a zone change, so this is the thing that keeps the override true
	-- — cheap enough at a few hundred parts every SKIN_SWEEP_INTERVAL.
	local since = 0
	RunService.Heartbeat:Connect(function(deltaTime: number)
		if active == nil then
			return
		end
		since += deltaTime
		if since < Constants.SKIN_SWEEP_INTERVAL then
			return
		end
		since = 0
		applyTo(pieceParts(), active.material)
	end)
end

return TowerSkinController
