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
-- append, don't renumber. Id 4 is retired: it was "Glow", a Neon skin that rolled
-- for free. Neon is a *purchase* now (the Store's `skins.neon` pack overrides the
-- material on every block for whoever owns it), and a stock skin that already
-- glowed would have made the thing being sold look like nothing.

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
	-- How far this skin deforms when it lands, 0 = rigid, 1 = full jelly. Read by
	-- TowerJellyController, which scales its whole squash-and-stretch output by
	-- it — so this is "how soft does this material look", in one number, and a
	-- skin that reads as stone should be near zero however good the wobble is.
	squish: number,
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
		-- Not zero. A dry knock still gives a little on the frame it lands, and
		-- flat zero next to a Needoh reads as the effect having failed rather than
		-- as the material being hard.
		squish = 0.15,
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
		-- The reference squish. Everything else is graded against this one.
		squish = 1,
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
		-- Softer than Needoh but it holds its shape: butter dents, jelly wobbles.
		-- Most of the difference the eye reads between these two is that Needoh
		-- comes back with an overshoot and this doesn't get far enough to.
		squish = 0.75,
	},
	{
		id = 5,
		name = "Wood",
		color = Color3.fromRGB(168, 116, 68),
		material = Enum.Material.WoodPlanks,
		-- Placeholder: Assets.Sounds.Stamp, a short thunk that isn't the Classic
		-- knock. Worth auditioning against the ASMR kit's own wood sample.
		impactSound = "rbxassetid://521293072",
		volume = 0.6,
		pitchRange = { 0.8, 1.05 },
		-- Wood, Grass and Concrete are the rare tier: one weight each against the
		-- stock three's 3-4, so any one of them turns up about a third as often as
		-- Butter and the three together are under a quarter of all pieces. They're
		-- the ends of the squish scale (0.06 to 0.45) rather than the middle of it,
		-- and a tower built mostly out of the extremes stops reading as a range.
		weight = 1,
		-- The rigid end of the range. A plank that wobbled would stop being wood.
		squish = 0.12,
	},
	{
		id = 6,
		name = "Grass",
		color = Color3.fromRGB(126, 190, 88),
		material = Enum.Material.Grass,
		-- Placeholder: Assets.Sounds.Drop2, the most muted thing in the library.
		impactSound = "rbxassetid://535716488",
		settleSound = RELEASE_SOUND,
		volume = 0.5,
		pitchRange = { 0.85, 1.05 },
		weight = 1,
		-- Turf gives underfoot without springing back — a soft landing and a dead
		-- one, which is the low-damping end rather than the low-amplitude end.
		squish = 0.45,
	},
	{
		id = 7,
		name = "Concrete",
		color = Color3.fromRGB(148, 148, 152),
		material = Enum.Material.Concrete,
		-- Placeholder: Assets.Sounds.NormalBlockCollision, pitched down at the
		-- bottom of its range so it reads heavier than Classic's knock.
		impactSound = "rbxassetid://120925282182940",
		volume = 0.65,
		pitchRange = { 0.7, 0.9 },
		weight = 1,
		-- The floor of the scale: it lands and it stops.
		squish = 0.06,
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
