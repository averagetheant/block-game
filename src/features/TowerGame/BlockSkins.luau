-- How a block looks and, more to the point, what it sounds like when it lands.
--
-- Every piece rolls a skin at spawn. The sounds come from the ASMR kit in the
-- place (Agus_Fellini2), so the ids here are the ones that kit actually ships —
-- don't invent new ones without checking they resolve, or a skin goes silent.
--
-- Note the skins change *surface and sound only*, never geometry and no longer
-- colour — every piece rolls its own random hue (see TowerService.randomColor),
-- so `color` here is only a fallback for anything that renders a skin outside
-- the game, like a story. Surface is material plus, for Duck alone, a tiled
-- `texture` over it. The ASMR kit's meshes (a squishy Needoh, a stick of
-- butter) are lovely but they're not cubes, and a tetromino cell has to be a
-- cube for the stacking to read honestly. The squish is carried by the sound.
--
-- `id` goes over the wire and is what the HUD would look up, so ids are stable —
-- append, don't renumber. Id 4 is retired: it was "Glow", a Neon skin that rolled
-- for free. Neon is a *purchase* now (the Store's `skins.neon` pack overrides the
-- material on every block for whoever owns it), and a stock skin that already
-- glowed would have made the thing being sold look like nothing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type Skin = {
	id: number,
	name: string,
	color: Color3,
	material: Enum.Material,
	transparency: number?,
	-- Tiled over every face of the block. nil for the ordinary skins, whose look
	-- is entirely material and colour — a Texture is a decal on top of that, so it
	-- survives the hue roll and reads as a pattern *on* the block rather than as
	-- the block's own surface. Tiled rather than stretched: a piece is one to four
	-- cells depending on the shape, and a stretched image would be a different
	-- size on an I than on an O.
	texture: string?,
	-- Played on the first solid impact.
	impactSound: string,
	-- A folder of interchangeable takes under `Assets.Sounds.Impacts`, by name.
	-- One is picked at random *per landing* (see `BlockSkins.impactIdFor`), which
	-- is what six near-identical grass footsteps are for: the ear catches a
	-- repeated sample long before it catches a repeated pitch, and a tower is
	-- forty landings of the same material.
	--
	-- Outranks `impactCue` and `impactSound`, both of which stay as the fallback —
	-- Rojo doesn't sync the folder, so a place without it still lands audibly.
	impactFolder: string?,
	-- A Studio-authored Sound to take the impact id from, by name, instead of
	-- writing an id here. For a sound a human dropped into the place rather than
	-- one picked off the catalogue — see `BlockSkins.impactIdFor`, which is what
	-- resolves it. Wins over `impactSound`, which stays as the fallback for when
	-- the instance isn't there.
	impactCue: string?,
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

-- ------------------------------------------------------------------ the duck --
-- Pulled out of the entry below only because the three of them are what you'd
-- come to this file to change. The yellow is HSV (0.127, 0.76, 1.0), which is the
-- family `skins.duck` rolls its blocks in — keep the two together or the shop
-- card stops matching the tower it's selling.
local DUCK_YELLOW = Color3.fromRGB(255, 209, 61)
local DUCK_TEXTURE = "rbxassetid://11113512609"
-- The Sound instance the quack comes from, by name. See `impactIdFor`.
local DUCK_CUE = "Quack"

local BlockSkins = {}

BlockSkins.List = {
	{
		id = 1,
		name = "Classic",
		color = Color3.fromRGB(96, 100, 112),
		material = Enum.Material.Concrete,
		-- The default block, and now on Needoh's folder as well: the squish takes
		-- are the game's house landing sound, and the skin most blocks roll is the
		-- last one that should be the exception to it.
		--
		-- Assets.Sounds.NormalBlockCollision — the plain, weighty knock this used
		-- to land on — stays as the fallback for a place without the folder.
		impactFolder = "Needoh",
		impactSound = "rbxassetid://120925282182940",
		-- Up from 0.55, which was set against that dry knock. Levelled with Needoh
		-- and Butter rather than nudged to a number of its own: the three now play
		-- the *same* takes, and one sample landing at two loudnesses depending on
		-- which skin rolled it is the kind of difference that reads as a bug.
		volume = 0.7,
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
		-- Seven squishes in Assets.Sounds.Impacts.Needoh, one per landing. The
		-- id below is the fallback for a place that doesn't have the folder.
		impactFolder = "Needoh",
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
		-- Needoh's folder, shared rather than copied: the two are the same family
		-- of soft landing, and one folder means adding a squish take improves both.
		-- Its own `impactSound` below stays as the fallback — the same sample the
		-- folder's second take uses, so a place without the folder sounds the way
		-- this skin always did.
		impactFolder = "Needoh",
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
		-- Five wood-panel takes in Assets.Sounds.Impacts.Wood. `Stamp` stays as
		-- the fallback: a short thunk that isn't the Classic knock, picked so the
		-- skin is never silent without the folder.
		impactFolder = "Wood",
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
		-- Six footsteps in Assets.Sounds.Impacts.Grass, wet and dry mixed. `Drop2`
		-- — the most muted thing in the library — stays as the fallback.
		impactFolder = "Grass",
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
	{
		id = 8,
		name = "Duck",
		-- The only skin whose colour is *the point* rather than a fallback: a duck
		-- that rolled a random hue is not a duck. The pack pins the hue too (see
		-- SkinPacks `skins.duck`), so this value is what a card or a story draws
		-- and the pack's roll is what the tower wears — kept in the same family
		-- deliberately, or the shop tile would lie about the product.
		color = DUCK_YELLOW,
		material = Enum.Material.SmoothPlastic,
		texture = DUCK_TEXTURE,
		-- Falls back to the Classic knock if the Quack Sound isn't in the place, so
		-- a missing asset costs the joke and not the landing.
		impactSound = "rbxassetid://120925282182940",
		impactCue = DUCK_CUE,
		volume = 0.7,
		-- Wider than the rest and centred slightly high. A quack is a voice, not a
		-- surface, and two identical quacks in a row is the one thing that would
		-- make it read as a broken loop rather than as a flock.
		pitchRange = { 0.85, 1.25 },
		-- Never rolls. `weight = 0` can't be reached by the walk in
		-- `BlockSkins.random`, which is the whole point: the only route to this skin
		-- is the pack, and the pack is only ever granted (DuckSkinService). It stays
		-- in the list because everything else — `get`, the cmdr `skin` command, the
		-- shop card's preview — looks skins up here.
		weight = 0,
		-- Rubber, near the top of the scale but under Needoh. It's a bath toy: it
		-- gives, and it comes back.
		squish = 0.8,
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

-- The cue library: `Assets.Sounds`, the house folder for a sound a human tuned in
-- Studio (see Shared.audio). Both lookups below start here.
local function soundLibrary(): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	return if assets then assets:FindFirstChild("Sounds") else nil
end

-- Where a Studio-authored impact Sound is looked for, in order. The cue library
-- is where one of these belongs; Workspace is checked after it because that's
-- where a Sound dropped into the place without being filed away ends up, and a
-- skin going silent over which folder the instance sits in would be a
-- frustrating way to lose a sound.
local function cueHolders(): { Instance }
	local holders = {}
	local sounds = soundLibrary()
	if sounds then
		table.insert(holders, sounds)
	end
	table.insert(holders, workspace)
	return holders
end

-- Where the per-material impact folders live: `Assets.Sounds.Impacts.<name>`,
-- one folder per material, each holding as many takes as somebody felt like
-- recording.
local IMPACT_FOLDER = "Impacts"

local warnedFolders: { [string]: boolean } = {}
-- Memoized on success only, the same rule as `resolvedCues` below and for a
-- sharper version of the same reason: this one is read on *every landing*, so a
-- hit has to be a table lookup. The contents can't change without the place
-- being edited.
local resolvedVariants: { [string]: { string } } = {}

-- Every take in one impact folder, or nil if the folder isn't there or is empty.
local function variantsFor(folderName: string): { string }?
	local cached = resolvedVariants[folderName]
	if cached then
		return cached
	end

	local sounds = soundLibrary()
	local impacts = if sounds then sounds:FindFirstChild(IMPACT_FOLDER) else nil
	local folder = if impacts then impacts:FindFirstChild(folderName) else nil
	if folder == nil then
		return nil
	end

	local ids = {}
	for _, child in folder:GetChildren() do
		-- An empty SoundId is a Sound somebody added and never filled in; taking
		-- it would cache silence into the rotation forever.
		if child:IsA("Sound") and child.SoundId ~= "" then
			table.insert(ids, child.SoundId)
		end
	end
	if #ids == 0 then
		return nil
	end

	resolvedVariants[folderName] = ids
	return ids
end

local warnedCues: { [string]: boolean } = {}
-- Memoized on success only. This runs once per block spawned, and a miss has to
-- stay cheap enough to run on every one of them — but a hit is a value that
-- can't change without the place being edited, so it's looked up once.
local resolvedCues: { [string]: string } = {}

-- The asset id this skin's impact should play.
--
-- Resolved rather than stored because a skin may name Studio-authored Sounds
-- instead of an id — a whole folder of takes (`impactFolder`) or a single named
-- one (`impactCue`) — and Rojo doesn't sync instances, so those ids only exist in
-- the place file. Only the *id* is taken, never the instance: the skin already
-- owns its own volume and pitch range, and cloning the Sound would put a second,
-- quieter opinion about both onto every block.
--
-- Called per landing rather than per block, which is what makes a folder read as
-- variety instead of as one sample assigned at spawn. Cheap by construction: a
-- resolved folder is a cached array and the roll is one `math.random`.
--
-- Each step falls back to the next, with a one-time warning: a missing sound
-- should cost the flavour, not the landing.
function BlockSkins.impactIdFor(skin: Skin): string
	local folder = skin.impactFolder
	if folder ~= nil then
		local ids = variantsFor(folder)
		if ids ~= nil then
			return ids[math.random(#ids)]
		end
		if not warnedFolders[folder] then
			warnedFolders[folder] = true
			warn(
				`[BlockSkins] no Sounds under Assets.Sounds.{IMPACT_FOLDER}.{folder}; `
					.. `{skin.name} falls back to its single impact`
			)
		end
	end

	local cue = skin.impactCue
	if cue == nil then
		return skin.impactSound
	end
	local cached = resolvedCues[cue]
	if cached then
		return cached
	end

	-- Direct children only, in both holders. Recursing Workspace would mean
	-- walking every block in the tower to spawn the next one, and a Sound left
	-- loose in the place is a direct child of it anyway.
	for _, holder in cueHolders() do
		local sound = holder:FindFirstChild(cue)
		-- An empty SoundId is a Sound someone added and never filled in; treating
		-- it as a hit would cache silence forever.
		if sound and sound:IsA("Sound") and sound.SoundId ~= "" then
			resolvedCues[cue] = sound.SoundId
			return sound.SoundId
		end
	end

	if not warnedCues[cue] then
		warnedCues[cue] = true
		warn(`[BlockSkins] no Sound named "{cue}" in Assets.Sounds or Workspace; {skin.name} falls back to its default impact`)
	end
	return skin.impactSound
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
