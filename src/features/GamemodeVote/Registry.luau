--!strict
-- The list of gamemodes that can be voted for.
--
-- GamemodeVote owns the *mechanism* — the poll, the clock, the tally, the
-- screen. It owns no modes. Every mode is registered by the feature that
-- implements it, from a sibling `Gamemode.luau` picked up by the auto-discovery
-- loop in init.luau, so this feature names nobody and a game with no gamemodes
-- registered simply never opens a vote.
--
-- `modifier` is opaque here on purpose: it's a payload the *registering* feature
-- hands itself back when its mode wins. GamemodeVote never reads inside it, so
-- adding a new kind of modifier needs no change in this folder.
--
-- Each realm has its own copy (Lua state is per-realm), so registration must
-- happen from shared code — which is what the discovery convention guarantees.
-- The client needs the names and icons to draw the panels; the server needs the
-- ids to validate a vote.

export type Gamemode = {
	id: string,
	name: string,
	icon: string,
	-- One short line under the name. Kept to a line — the panels are narrow.
	blurb: string?,
	-- Sort order across the panels (low → high). Ties break by name.
	order: number?,
	-- Always on the ballot, never one of the random picks. For the "leave it
	-- alone" option a poll needs: a ballot of nothing but twists gives the
	-- players no way to decline one. GamemodeVote doesn't know or care *which*
	-- mode that is — the registering feature says so.
	pinned: boolean?,
	-- Handed back to the registering feature when this mode wins. Never read here.
	modifier: any?,
}

local Registry = {}

local modes: { [string]: Gamemode } = {}

function Registry.register(mode: Gamemode)
	if typeof(mode) ~= "table" or typeof(mode.id) ~= "string" or mode.id == "" then
		warn("[GamemodeVote] register() needs a table with a non-empty string id")
		return
	end
	if modes[mode.id] ~= nil then
		warn(`[GamemodeVote] gamemode "{mode.id}" registered twice; overwriting`)
	end
	modes[mode.id] = mode
end

function Registry.get(id: string): Gamemode?
	return modes[id]
end

-- Every registered mode in display order. Sorted rather than returned in
-- discovery order so both realms — and every client — draw the same panels in
-- the same places.
function Registry.list(): { Gamemode }
	local list = {}
	for _, mode in modes do
		table.insert(list, mode)
	end
	table.sort(list, function(a, b)
		local orderA = a.order or 0
		local orderB = b.order or 0
		if orderA ~= orderB then
			return orderA < orderB
		end
		return a.name < b.name
	end)
	return list
end

------------------------------------------------------------------------------
-- Auto-discovery
------------------------------------------------------------------------------
-- Walk the Features tree and require any feature's `Gamemode.luau`. That module
-- returns `function(GamemodeVote) ... end`; called with this table, it registers
-- whatever modes the feature implements. The indirection (a function rather than
-- a direct require of this feature) is what keeps a registering feature from
-- importing GamemodeVote and closing a require cycle.
--
-- This lives in the registry rather than the feature's init.luau — which is
-- where PlayerData and Settings put theirs — because the server entry script
-- only loads `*Service` modules, so a server-side consumer requires this file
-- and never the init. Hanging discovery off the init would leave the server's
-- ballot empty while every client's was full. Registry is also the realm-neutral
-- half: the init additionally pulls in the React UI, which the server has no use
-- for.
do
	local Features = script.Parent.Parent
	for _, featureModule in Features:GetChildren() do
		-- Our own feature folder: it has no Gamemode.luau, but skip it anyway so
		-- the intent is obvious.
		if featureModule == script.Parent then
			continue
		end
		local mod = featureModule:FindFirstChild("Gamemode")
		if mod == nil or not mod:IsA("ModuleScript") then
			continue
		end

		local ok, result = pcall(require, mod)
		if not ok then
			warn(`[GamemodeVote] failed to require {mod:GetFullName()}: {result}`)
			continue
		end
		if typeof(result) ~= "function" then
			warn(
				`[GamemodeVote] {mod:GetFullName()} must return function(GamemodeVote); `
					.. `got {typeof(result)}`
			)
			continue
		end

		local okCall, err = pcall(result, Registry)
		if not okCall then
			warn(`[GamemodeVote] registration error in {mod:GetFullName()}: {err}`)
		end
	end
end

return Registry
