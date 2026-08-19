--!strict
-- The left rail's contents, contributed by whoever wants to be on it.
--
-- Sidebar owns the *mechanism* (a column of icons, the frame each one opens);
-- every entry is owned by the feature that put it there. So adding Shop to the
-- rail is a file inside the Shop feature, never an edit to this one — see
-- CLAUDE.md § "Features extend each other through registration".
--
-- Two ways in, because entries come in two flavours:
--
--   * A sibling `Sidebar.luau` (shared realm, auto-discovered by init.luau) for
--     the declarative kind — an icon that opens a window. Both realms load it,
--     so it must not reach for realm-specific code.
--   * A `*Presentation.client.luau` calling registerEntry directly, for entries
--     whose click does something client-only (prompt a purchase, fire a
--     controller). Those can't live in a shared file.
--
-- Unlike the Settings registry this one is deliberately *not* sealed after
-- discovery: the client-realm route above is a legitimate second window, and no
-- server-side validation reads this, so the two realms disagreeing is harmless
-- (the server never renders a sidebar).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Packages.Signal)

-- Which cluster of the rail an entry belongs to. They render as two columns with
-- a gap between them: navigation on top, one-shot actions underneath.
export type Group = "menu" | "actions"

export type Entry = {
	-- React child key + UIShell frame id fallback. Unique across the rail.
	id: string,
	icon: string,
	label: string,
	-- Sort order inside the group (low → high). Ties break by label.
	order: number?,
	-- Defaults to "menu".
	group: Group?,
	-- Set to open a UIShell frame on click. The frame and its Window are
	-- rendered by the rail; the *contents* come from the screen registry
	-- (`UIRegistry.registerScreen(frameId, element)`), so this feature never
	-- names what's inside. Defaults to `id` when `onClick` isn't set either.
	frameId: string?,
	-- Window chrome for that frame. All optional; the title defaults to label.
	windowTitle: string?,
	titleVariant: string?,
	windowSize: UDim2?,
	-- Runs instead of opening a frame. An entry with both opens the frame and
	-- then runs this, which is almost never what you want — pick one.
	onClick: (() -> ())?,
	-- Whether the entry belongs on the rail *right now*. Called every time the
	-- rail reads the registry; nil means always, which is nearly every entry.
	--
	-- For an entry that only applies to part of the game — a gamemode's own
	-- action button, something that unlocks — so the owning feature can take it
	-- off the rail without unregistering and re-registering it, and without this
	-- file learning what a gamemode is.
	--
	-- The rail only re-reads on `Changed`, so a feature whose answer here changes
	-- has to say so: call `Sidebar.refresh()` when it flips. Nobody else can know
	-- that it did.
	visible: (() -> boolean)?,
}

local Registry = {}

-- Fires whenever an entry is registered, so a rail already on screen picks up a
-- late registration instead of needing a remount.
Registry.Changed = Signal.new()

local entries: { [string]: Entry } = {}

function Registry.registerEntry(def: Entry)
	if entries[def.id] ~= nil then
		warn(`[Sidebar] entry "{def.id}" already registered; overwriting`)
	end
	entries[def.id] = def
	Registry.Changed:Fire()
end

-- Tell the rail to re-read the registry. For a feature whose `visible` answer
-- depends on game state — the registry can't see that change, and the entry
-- itself hasn't changed, so registering again would be a lie (and a warning).
function Registry.refresh()
	Registry.Changed:Fire()
end

function Registry.getEntry(id: string): Entry?
	return entries[id]
end

-- The frame id an entry opens, or nil if it's a plain action button.
function Registry.frameIdOf(entry: Entry): string?
	if entry.onClick ~= nil and entry.frameId == nil then
		return nil
	end
	return entry.frameId or entry.id
end

local function byOrder(a: Entry, b: Entry): boolean
	local ao = a.order or math.huge
	local bo = b.order or math.huge
	if ao ~= bo then
		return ao < bo
	end
	return a.label < b.label
end

-- Every entry in `group` that applies right now, sorted. Returns a fresh list
-- each call.
function Registry.list(group: Group?): { Entry }
	local wanted = group or "menu"
	local result: { Entry } = {}
	for _, entry in entries do
		if (entry.group or "menu") ~= wanted then
			continue
		end
		if entry.visible and not entry.visible() then
			continue
		end
		table.insert(result, entry)
	end
	table.sort(result, byOrder)
	return result
end

return Registry
