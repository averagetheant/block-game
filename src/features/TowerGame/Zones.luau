-- Zones — what the world turns into after each checkpoint.
--
-- A zone is picked when a checkpoint is cleared. Most are `normal` (calm, just a
-- new sky); the rest each bend one rule of the game. The kind travels in the
-- state packet, so the server enforces the physics half and every client applies
-- the same visual half from these definitions.
--
-- They arrive on a *cadence*, not a roll: two normal zones, then a special. See
-- `Zones.next`.
--
-- `id` goes over the wire — append, don't renumber.
--
-- Assets these names refer to live in `ReplicatedStorage.Assets.Zones` and are
-- authored in Studio (Rojo doesn't sync them). A missing one degrades to "no
-- change" rather than erroring; see TowerZoneController.

export type Kind = "normal" | "retro" | "snowy" | "stormy" | "space" | "foggy" | "night"

export type Zone = {
	id: number,
	kind: Kind,
	name: string,
	-- Shown in the warning banner. nil for normal zones, which don't warn.
	warning: string?,
	-- Child of `Assets.Zones` holding this zone's Sky. Normal zones leave this
	-- nil and roll one of the skies in `Assets.Zones.Normal` instead.
	sky: string?,
	tint: Color3,
	-- Rarity — higher shows up more often. The classic run never rolls for a
	-- normal zone (the cadence in `Zones.next` places those), so this only ever
	-- ranked the specials against each other there. `Zones.roll` rolls the whole
	-- list, so the normal zone's weight is what decides how much of a PVP match
	-- is played in plain weather.
	weight: number,
	-- World gravity while this zone is up. nil means Roblox's default, which is
	-- what every zone but Space wants. The server writes `workspace.Gravity`, so
	-- this is one of the physics halves a client can't fake.
	gravity: number?,
}

local Zones = {}

-- Roblox's out-of-the-box gravity, restored by every zone that doesn't name its
-- own. Kept here rather than in Constants so a zone's gravity and its fallback
-- can't drift apart.
Zones.DEFAULT_GRAVITY = 196.2

Zones.List = {
	{
		id = 1,
		kind = "normal",
		name = "Clear Skies",
		tint = Color3.fromRGB(150, 205, 255),
		weight = 6,
	},
	{
		id = 2,
		kind = "retro",
		name = "Retro Zone",
		warning = "Blocks go old-school",
		sky = "Retro",
		tint = Color3.fromRGB(255, 214, 120),
		weight = 2,
	},
	{
		id = 3,
		kind = "snowy",
		name = "Snowy Zone",
		warning = "Blocks are slippery!",
		sky = "Snowy",
		tint = Color3.fromRGB(198, 236, 255),
		weight = 2,
	},
	{
		id = 4,
		kind = "stormy",
		name = "Stormy Zone",
		warning = "Lightning is striking the tower!",
		sky = "Stormy",
		tint = Color3.fromRGB(150, 160, 200),
		weight = 2,
	},
	{
		id = 5,
		kind = "space",
		name = "Space Zone",
		warning = "Gravity is low!",
		sky = "Space",
		tint = Color3.fromRGB(176, 150, 255),
		weight = 2,
		-- A sixth of normal: pieces drift down slowly enough to place with care,
		-- and a knocked tower takes an age to come apart.
		gravity = 30,
	},
	{
		id = 6,
		kind = "foggy",
		name = "Foggy Zone",
		warning = "You can barely see!",
		sky = "Foggy",
		tint = Color3.fromRGB(198, 202, 210),
		weight = 2,
	},
	{
		id = 7,
		kind = "night",
		name = "Night Zone",
		warning = "Lights out — the blocks glow!",
		sky = "Night",
		tint = Color3.fromRGB(120, 128, 190),
		weight = 2,
	},
} :: { Zone }

local byId: { [number]: Zone } = {}
for _, zone in Zones.List do
	byId[zone.id] = zone
end

-- Zone 1 (normal) is where every run starts.
Zones.DEFAULT_ID = 1

function Zones.get(id: number): Zone
	return byId[id] or byId[Zones.DEFAULT_ID]
end

function Zones.gravityOf(id: number): number
	return Zones.get(id).gravity or Zones.DEFAULT_GRAVITY
end

-- How many normal zones run between specials. The hazard is the punctuation, not
-- the sentence: back-to-back specials stop reading as an escalation and start
-- reading as the game's default state, and the plain zones are what give the
-- players a stretch to build in.
Zones.NORMALS_PER_SPECIAL = 2

-- The next zone, given how many have already been cleared.
--
-- Deliberately a *cadence* rather than a weighted roll. A roll can hand out four
-- specials in a row or none for six floors, and neither is the shape of a run
-- anyone wants: this makes the rhythm two calm floors then a twist, every time,
-- while leaving *which* twist random.
--
-- `avoidId` keeps the same special from landing twice running — repeating a
-- hazard reads as the game glitching rather than escalating.
function Zones.next(cleared: number, avoidId: number?): Zone
	-- The +1 is because `cleared` counts zones behind us and this is picking the
	-- one ahead: with a cadence of 2, that puts specials on the 3rd, 6th, 9th…
	if (cleared + 1) % (Zones.NORMALS_PER_SPECIAL + 1) ~= 0 then
		return byId[Zones.DEFAULT_ID]
	end

	local specials = {}
	for _, zone in Zones.List do
		if zone.kind ~= "normal" and zone.id ~= avoidId then
			table.insert(specials, zone)
		end
	end
	-- Only one special exists and we just played it: better to repeat than to
	-- silently drop back to a normal zone the cadence promised wouldn't be here.
	if #specials == 0 then
		return byId[avoidId or Zones.DEFAULT_ID] or byId[Zones.DEFAULT_ID]
	end

	local total = 0
	for _, zone in specials do
		total += zone.weight
	end
	local roll = math.random() * total
	for _, zone in specials do
		roll -= zone.weight
		if roll <= 0 then
			return zone
		end
	end
	return specials[#specials]
end

-- A zone rolled from the whole list, weights and all, avoiding the one that's up.
--
-- The counterpart to `Zones.next`, for a mode with nothing to count. The cadence
-- is measured in *checkpoints cleared*, and a PVP match clears none — it changes
-- zone on a clock instead, so there is no "third floor" to put a special on. A
-- plain roll is also the right shape for it: a match is three minutes, so a run
-- of two calm zones would be most of the round, and the weights already say a
-- normal zone should come up about three times as often as any one special.
--
-- `avoidId` keeps the same zone from being rolled twice running, which would
-- otherwise read as the clock having failed rather than as luck.
function Zones.roll(avoidId: number?): Zone
	local pool = {}
	local total = 0
	for _, zone in Zones.List do
		if zone.id == avoidId then
			continue
		end
		table.insert(pool, zone)
		total += zone.weight
	end
	-- Only one zone exists and it's the one we're avoiding. Repeating it beats
	-- returning nothing.
	if total <= 0 then
		return byId[avoidId or Zones.DEFAULT_ID] or byId[Zones.DEFAULT_ID]
	end

	local roll = math.random() * total
	for _, zone in pool do
		roll -= zone.weight
		if roll <= 0 then
			return zone
		end
	end
	return pool[#pool]
end

return Zones
