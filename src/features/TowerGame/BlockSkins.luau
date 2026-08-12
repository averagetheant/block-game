-- How a block looks and, more to the point, what it sounds like when it lands.
--
-- Every piece rolls a skin at spawn. The sounds come from the ASMR kit in the
-- place (Agus_Fellini2), so the ids here are the ones that kit actually ships —
-- don't invent new ones without checking they resolve, or a skin goes silent.
--
-- Note the skins change *material and sound only*, never geometry and no longer
-- colour — every piece rolls its own random hue (see TowerService.randomColor),
-- so `color` here is only a fallback for anything that renders a skin outside
-- the game, like a story. The ASMR kit's meshes (a squishy Needoh, a stick of
-- butter) are lovely but they're not cubes, and a tetromino cell has to be a
-- cube for the stacking to read honestly. The squish is carried by the sound.
--
-- `id` goes over the wire and is what the HUD would look up, so ids are stable —
-- append, don't renumber.

export type Skin = {
	id: number,
	name: string,
	color: Color3,
	material: Enum.Material,
	transparency: number?,
	-- Played on the first solid impact.
	impactSound: string,
	-- Played once the piece comes to rest, if set — the "settle" half of the
	-- squish. The kit shares one release sound across its squishy props.
	settleSound: string?,
	volume: number,
	-- Pitch is randomized inside this range per impact so a tower of the same
	-- skin doesn't sound like a machine.
	pitchRange: { number },
	-- Rarity weight; higher shows up more often.
	weight: number,
}

local RELEASE_SOUND = "rbxassetid://133222321566847"

local BlockSkins = {}

BlockSkins.List = {
	{
		id = 1,
		name = "Classic",
		color = Color3.fromRGB(96, 100, 112),
		material = Enum.Material.Concrete,
		-- Assets.Sounds.NormalBlockCollision — the plain, weighty knock the rest
		-- of the skins are flavoured against.
		impactSound = "rbxassetid://120925282182940",
		volume = 0.55,
		pitchRange = { 0.85, 1.1 },
		weight = 4,
	},
	{
		id = 2,
		name = "Needoh",
		color = Color3.fromRGB(255, 152, 220),
		material = Enum.Material.Glass,
		transparency = 0.15,
		impactSound = "rbxassetid://87295773843957",
		settleSound = RELEASE_SOUND,
		volume = 0.7,
		pitchRange = { 0.9, 1.15 },
		weight = 3,
	},
	{
		id = 3,
		name = "Butter",
		color = Color3.fromRGB(255, 201, 93),
		material = Enum.Material.SmoothPlastic,
		impactSound = "rbxassetid://116062165012558",
		settleSound = RELEASE_SOUND,
		volume = 0.7,
		pitchRange = { 0.9, 1.15 },
		weight = 3,
	},
	{
		id = 4,
		name = "Glow",
		color = Color3.fromRGB(120, 220, 255),
		material = Enum.Material.Neon,
		impactSound = "rbxassetid://140323850218372",
		volume = 0.6,
		pitchRange = { 0.95, 1.2 },
		weight = 2,
	},
} :: { Skin }

local byId: { [number]: Skin } = {}
local totalWeight = 0
for _, skin in BlockSkins.List do
	byId[skin.id] = skin
	totalWeight += skin.weight
end

function BlockSkins.get(id: number): Skin?
	return byId[id]
end

function BlockSkins.random(): Skin
	local roll = math.random() * totalWeight
	for _, skin in BlockSkins.List do
		roll -= skin.weight
		if roll <= 0 then
			return skin
		end
	end
	return BlockSkins.List[1]
end

return BlockSkins
