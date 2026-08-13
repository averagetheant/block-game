-- Zones — what the world turns into after each checkpoint.
--
-- A zone is picked when a checkpoint is cleared. Most are `normal` (calm, just a
-- new sky); the rest each bend one rule of the game. The kind travels in the
-- state packet, so the server enforces the physics half and every client applies
-- the same visual half from these definitions.
--
-- `id` goes over the wire — append, don't renumber.
--
-- Assets these names refer to live in `ReplicatedStorage.Assets.Zones` and are
-- authored in Studio (Rojo doesn't sync them). A missing one degrades to "no
-- change" rather than erroring; see TowerZoneController.

export type Kind = "normal" | "retro" | "snowy" | "stormy" | "space"

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
		warning = "Wind is pushing the tower!",
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
} :: { Zone }

local byId: { [number]: Zone } = {}
local totalWeight = 0
for _, zone in Zones.List do
	byId[zone.id] = zone
	totalWeight += zone.weight
end

-- Zone 1 (normal) is where every run starts.
Zones.DEFAULT_ID = 1

function Zones.get(id: number): Zone
	return byId[id] or byId[Zones.DEFAULT_ID]
end

function Zones.gravityOf(id: number): number
	return Zones.get(id).gravity or Zones.DEFAULT_GRAVITY
end

-- Weighted pick. `avoidId` keeps the same special zone from landing twice in a
-- row — repeating a hazard reads as the game glitching rather than escalating.
function Zones.random(avoidId: number?): Zone
	for _ = 1, 8 do
		local roll = math.random() * totalWeight
		for _, zone in Zones.List do
			roll -= zone.weight
			if roll > 0 then
				continue
			end
			if zone.id == avoidId and zone.kind ~= "normal" then
				break
			end
			return zone
		end
	end
	return byId[Zones.DEFAULT_ID]
end

return Zones
