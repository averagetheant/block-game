--!strict
-- What the week actually gives out — declared by the features that own the
-- content, never by DailyRewards itself.
--
-- DailyRewards ships the *mechanism* (the run, the streak, the claim gate, the
-- window) and knows nothing about coins or packs. Two things get registered,
-- and they're separate because they have different owners:
--
--   * a **kind** — how to hand something over. Owned by the feature that owns
--     the thing: Store knows how to credit a currency and how to mark a pack
--     owned, so Store registers those kinds.
--   * a **day** — what slot N of the run gives. Owned by the feature whose
--     content it is: TowerGame's coins are TowerGame's to schedule.
--
-- Both come from a sibling `DailyRewards.luau` that the auto-discovery loop in
-- init.luau requires on both realms:
--
--   -- src/features/Pets/DailyRewards.luau
--   return function(DailyRewards)
--       DailyRewards.registerKind({
--           id = "pet",
--           grant = function(player, payload)
--               -- Server-only body. The module itself loads on both realms, so
--               -- the ServerScriptService require has to live in here, where
--               -- only the server ever runs it (same trick as a Cmdr `Run`).
--               local ServerScriptService = game:GetService("ServerScriptService")
--               local PetsService = require(ServerScriptService.Features.Pets.PetsService)
--               return PetsService.grantPet(player, payload.petId)
--           end,
--       })
--       DailyRewards.registerDay({ day = 5, kind = "pet", payload = { petId = "corgi" },
--           name = "Corgi", icon = … })
--   end
--
-- Both realms register the same set, which is the point: the server validates a
-- claim against this registry, so a client-only day would be a claim the server
-- rejects and a server-only one would be invisible in the window. That's also
-- why it seals after discovery.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Packages.Signal)
local Constants = require(ReplicatedStorage.Features.DailyRewards.Constants)

-- Returns true when the player actually received the thing. False means "not
-- now" — the claim is refused and the day stays available, rather than being
-- burned on a grant that didn't land (a full inventory, a service still
-- starting, a pack that left the catalog).
export type Grant = (player: Player, payload: any) -> boolean

export type Kind = {
	id: string,
	grant: Grant,
}

export type Day = {
	-- 1..Constants.CYCLE_DAYS. The last day is the grand prize.
	day: number,
	-- A registered kind id. A day whose kind never registered can't be claimed;
	-- the window still draws it, so a missing grant reads as a content bug
	-- rather than a hole in the week.
	kind: string,
	-- Handed to the kind's grant verbatim. Shape is the kind's business.
	payload: any?,
	-- Display. `name` is short by necessity — it's overlaid on the card art at
	-- the Large tier inside ~210px (see DailyRewardsUI).
	name: string,
	icon: string?,
	-- Second line, grand card only.
	caption: string?,
}

local Registry = {}

-- Fires on every registration so an open window picks up a late one.
Registry.Changed = Signal.new()

local kinds: { [string]: Kind } = {}
local days: { [number]: Day } = {}

-- Once the shared auto-discovery pass finishes the registry is sealed. A later
-- register* call is realm-specific code reaching in after load — exactly what
-- would let the two realms disagree about what day 3 gives, which is a claim
-- the server refuses and the player can't explain. Hard error at the call site
-- beats silent drift. (Same reasoning as the Settings and Store registries.)
local sealed = false

function Registry.seal()
	sealed = true
end

local function assertUnsealed(what: string, id: string)
	if not sealed then
		return
	end
	error(
		`[DailyRewards] {what} "{id}" registered after the registry was sealed. `
			.. `Register only from shared code (a sibling DailyRewards.luau picked up by `
			.. `auto-discovery), never from server- or client-only code — otherwise the `
			.. `two realms' registries diverge.`,
		2
	)
end

function Registry.registerKind(def: Kind)
	assertUnsealed("kind", def.id)
	if typeof(def.grant) ~= "function" then
		error(`[DailyRewards] kind "{def.id}" needs a grant function`, 2)
	end
	if kinds[def.id] ~= nil then
		warn(`[DailyRewards] kind "{def.id}" already registered; overwriting`)
	end
	kinds[def.id] = def
	Registry.Changed:Fire()
end

function Registry.registerDay(def: Day)
	assertUnsealed("day", tostring(def.day))
	if def.day ~= math.floor(def.day) or def.day < 1 or def.day > Constants.CYCLE_DAYS then
		error(
			`[DailyRewards] day {def.day} is outside the run (1..{Constants.CYCLE_DAYS}). `
				.. `Raise Constants.CYCLE_DAYS to lengthen the week.`,
			2
		)
	end
	-- Two features both claiming day 3 is a content collision, not a crash: the
	-- second wins so a game can deliberately override a shipped day, but it
	-- says so, because silently dropping one of them would be a reward nobody
	-- can find.
	local existing = days[def.day]
	if existing ~= nil then
		warn(`[DailyRewards] day {def.day} was "{existing.name}", now "{def.name}"`)
	end
	days[def.day] = def
	Registry.Changed:Fire()
end

function Registry.getKind(id: string): Kind?
	return kinds[id]
end

function Registry.getDay(day: number): Day?
	return days[day]
end

-- Every slot in the run, in order, with `false` where nothing registered. The
-- holes are deliberate: the window draws an unregistered day as a locked
-- "???" card rather than shortening the week, so a feature that was removed
-- leaves a visible gap instead of quietly renumbering everything after it.
function Registry.listDays(): { Day | false }
	local list: { Day | false } = {}
	for day = 1, Constants.CYCLE_DAYS do
		list[day] = days[day] or false
	end
	return list
end

return Registry
