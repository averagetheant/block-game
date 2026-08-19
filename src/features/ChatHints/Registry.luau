--!strict
-- The tips themselves, contributed by whoever owns the thing being explained.
--
-- ChatHints owns the *mechanism* — a clock, a channel, a rotation that doesn't
-- repeat — and knows nothing about towers, streaks or reactions. A hint about
-- the storm is a file inside TowerGame; a hint about the daily run is a file
-- inside DailyRewards. Adding one is never an edit to this feature (see
-- CLAUDE.md § "Features extend each other through registration").
--
-- One way in: a sibling `ChatHints.luau` returning `function(ChatHints) … end`,
-- auto-discovered by init.luau on both realms. It's a shared file, so keep the
-- text realm-agnostic — a hint is a string, not a lookup into client state.
--
-- Hint text is **rich text** and is written by whoever ships the feature, so
-- markup in it is deliberate (`<b>`, `<font>`) rather than something to escape.
-- Never build a hint out of a player's name or any other runtime string without
-- escaping it first — see TowerAnnounceController for that pattern.

local Registry = {}

export type Hint = {
	-- Unique across every feature's hints. Doubles as the "don't say the same
	-- thing twice in a row" key.
	id: string,
	-- One line, one idea. It lands in a chat window next to a tower, so it's
	-- read in a glance or not at all.
	text: string,
	-- Sort order (low → high). Only decides the *seed* order — the rotation is
	-- shuffled — so this is a tie-break for authors who want related hints
	-- grouped, not a schedule.
	order: number?,
}

local hints: { [string]: Hint } = {}

function Registry.registerHint(def: Hint)
	if hints[def.id] ~= nil then
		warn(`[ChatHints] hint "{def.id}" already registered; overwriting`)
	end
	hints[def.id] = def
end

-- Sugar for the common case: a feature declaring its whole set at once.
function Registry.registerHints(defs: { Hint })
	for _, def in defs do
		Registry.registerHint(def)
	end
end

local function byOrder(a: Hint, b: Hint): boolean
	local ao = a.order or math.huge
	local bo = b.order or math.huge
	if ao ~= bo then
		return ao < bo
	end
	return a.id < b.id
end

-- Every registered hint, sorted. Returns a fresh list each call, which is what
-- lets the controller pick up a late registration on its next rotation instead
-- of needing a signal.
function Registry.list(): { Hint }
	local result: { Hint } = {}
	for _, hint in hints do
		table.insert(result, hint)
	end
	table.sort(result, byOrder)
	return result
end

return Registry
