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
	-- The one line a player is ever shown about this zone, in either mode: the
	-- classic HUD's banner prints it and PVP's reel prints it when it lands (see
	-- `ZoneReel`). One string rather than two, so a zone cannot say one thing in a
	-- classic round and another in a match — to reword a zone, edit this and both
	-- modes follow.
	--
	-- Written in the banner's voice, which is the voice this game speaks in:
	-- short, present tense, about the trouble you are now in.
	--
	-- Every zone has one, the normal zone included. It used to be optional and to
	-- double as the "does this zone announce itself?" flag, which is why Clear
	-- Skies had none — but the reel lands on Clear Skies as often as on anything
	-- else and "nothing is out to get you" is an answer worth printing. Whether a
	-- zone announces itself is now asked of its `kind` instead, where it belongs
	-- (see TowerZoneController).
	warning: string,
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

-- The gravity every zone that doesn't name its own is played at. Kept here rather
-- than in Constants so a zone's gravity and its fallback can't drift apart.
--
-- 160, not Roblox's out-of-the-box 196.2. Lower gravity buys time twice over: a
-- piece reaches its terminal velocity later (see `Constants.FALL_SPEED`), and — the
-- half that actually decides whether a tower survives — a stack that starts to
-- lean topples slowly enough to be watched, sometimes slowly enough to be caught
-- by the next piece. At 196.2 a lean was a collapse before the player had read it
-- as a lean.
--
-- Not lower than this. Much under 150 and pieces hang rather than fall, the drop
-- clock starts to matter for the wrong reason, and the game stops reading as a
-- tower under load.
Zones.DEFAULT_GRAVITY = 160

Zones.List = {
	{
		id = 1,
		kind = "normal",
		name = "Clear Skies",
		warning = "Clear skies — nothing bends the rules!",
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

-- Whether a zone announces itself when it arrives — the classic HUD's banner and
-- the sound that goes with it.
--
-- Asked of the `kind` rather than of the copy. It used to be "does this zone have
-- a `warning` string", which worked only for as long as the normal zone had
-- nothing to say; now that every zone carries a line for the PVP reel to print,
-- a banner for "clear skies, nothing bends the rules" would be an announcement
-- that nothing happened, every third checkpoint.
function Zones.announces(zone: Zone): boolean
	return zone.kind ~= "normal"
end

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

-- A special zone, rolled by weight, avoiding the one that's up.
--
-- The shared half of `Zones.next`, and the whole of what a specials-only round
-- wants (the Wild Weather gamemode — see `Gamemodes.luau`): every zone that bends
-- a rule, weighted against each other, never the calm one.
--
-- `avoidId` keeps the same hazard from landing twice running — repeating one
-- reads as the game glitching rather than escalating. That matters more here than
-- anywhere else: a round that only ever picks specials asks this question every
-- checkpoint instead of every third one.
function Zones.rollSpecial(avoidId: number?): Zone
	local specials = {}
	local total = 0
	for _, zone in Zones.List do
		if zone.kind == "normal" or zone.id == avoidId then
			continue
		end
		table.insert(specials, zone)
		total += zone.weight
	end
	-- Only one special exists and we just played it: better to repeat than to
	-- silently hand back the normal zone the caller ruled out by asking.
	if #specials == 0 then
		return byId[avoidId or Zones.DEFAULT_ID] or byId[Zones.DEFAULT_ID]
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
	-- The cadence decides *whether* a special is due; `rollSpecial` decides which.
	-- Keeping the two apart is what let a gamemode ask for the second half on its
	-- own without a second copy of the weighted roll.
	return Zones.rollSpecial(avoidId)
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
