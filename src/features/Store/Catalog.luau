--!strict
-- Everything that can be bought, owned or equipped — declared by the features
-- that own the content, never by Store itself.
--
-- Store ships the mechanism (a currency balance, an owned set, an equipped
-- slot per kind, a shop that renders all of it) and knows nothing about blocks
-- or emojis. A feature declares its content in a sibling `Store.luau`, which
-- the auto-discovery loop in init.luau requires on both realms:
--
--   -- src/features/Pets/Store.luau
--   return function(Store)
--       Store.registerPack({ id = "pets.golden", kind = "pet", … })
--   end
--
-- Both realms register the same set, which matters: the server validates every
-- purchase against this registry, so a client-only entry would be a purchase
-- the server rejects, and a server-only one would be invisible in the shop.
-- That's why the registry seals after discovery — see Registry.seal in the
-- Settings feature for the same reasoning.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Packages.Signal)

-- What sort of thing a pack is. Also the key of the equipped slot it fills:
-- one equipped pack per kind, so buying a second skin pack doesn't stack.
-- Kinds are open — a feature can invent its own; the shop groups by them.
export type PackKind = string

-- The display side of a kind: what the shop calls that tab. Registered by the
-- feature that owns the content, so "skin" reads as "Skins" without Store ever
-- containing the word.
export type Kind = {
	id: PackKind,
	title: string,
	order: number?,
	-- Set false when the feature ships its own Inventory tab for this kind
	-- (Reactions does — assigning reactions to bar slots isn't "equip one pack").
	-- The shop tab is unaffected; buying is the same for every kind.
	inventory: boolean?,
}

export type Pack = {
	id: string,
	kind: PackKind,
	name: string,
	description: string,
	icon: string?,
	-- Price in `currency`. Zero means it's free (a starter pack the player
	-- effectively always owns) — it still has to be bought once so ownership
	-- has one representation.
	price: number,
	currency: string,
	-- Sort order within its kind (low → high). Ties break by name.
	order: number?,
	-- Gem palette for the pack's card.
	variant: string?,
}

-- A soft currency, e.g. the coins TowerGame pays out. `path` is the profile
-- path its balance lives at, which is how Store reads and debits a balance it
-- doesn't own: TowerGame's cash stays in TowerGame's slice.
export type Currency = {
	id: string,
	name: string,
	icon: string?,
	path: { string },
}

-- A developer product (bought with Robux).
--   "currency" → shown in the shop's Robux tab, grants `amount` of `currency`.
--   "action"   → not shown in the shop at all; it's a button somewhere else
--                (the sidebar's Nuke) whose effect a server handler runs.
export type ProductGroup = "currency" | "action"

export type Product = {
	id: number,
	name: string,
	description: string?,
	icon: string?,
	group: ProductGroup,
	order: number?,
	variant: string?,
	-- Currency grants only.
	amount: number?,
	currency: string?,
}

export type Gamepass = {
	id: number,
	name: string,
	description: string,
	icon: string?,
	order: number?,
	variant: string?,
}

-- An extra tab in the Inventory window, for content whose "equip" isn't just
-- picking one pack (the Reactions tab assigns reactions to bar slots). The
-- element is a React element, so this one is registered from a client-realm
-- presentation rather than a shared Store.luau.
export type InventoryTab = {
	id: string,
	title: string,
	order: number?,
	element: any,
}

local Catalog = {}

-- Fires on every registration so an open shop picks up a late one.
Catalog.Changed = Signal.new()

local kinds: { [string]: Kind } = {}
local packs: { [string]: Pack } = {}
local currencies: { [string]: Currency } = {}
local products: { [number]: Product } = {}
local gamepasses: { [number]: Gamepass } = {}
local inventoryTabs: { [string]: InventoryTab } = {}
-- packId → already complained about its missing kind. See listKinds.
local warnedKinds: { [string]: boolean } = {}

local sealed = false

-- Sealed after the shared discovery pass. Inventory tabs are exempt: they carry
-- a React element, so they can only come from the client realm, and nothing on
-- the server reads them.
function Catalog.seal()
	sealed = true
end

local function assertUnsealed(what: string, id: string | number)
	if not sealed then
		return
	end
	error(
		`[Store] {what} "{id}" registered after the catalog was sealed. Register `
			.. `only from a sibling Store.luau picked up by auto-discovery — otherwise `
			.. `the client offers something the server won't sell.`,
		2
	)
end

function Catalog.registerKind(def: Kind)
	assertUnsealed("kind", def.id)
	if kinds[def.id] ~= nil then
		warn(`[Store] kind "{def.id}" already registered; overwriting`)
	end
	kinds[def.id] = def
	Catalog.Changed:Fire()
end

function Catalog.registerPack(def: Pack)
	assertUnsealed("pack", def.id)
	if packs[def.id] ~= nil then
		warn(`[Store] pack "{def.id}" already registered; overwriting`)
	end
	packs[def.id] = def
	Catalog.Changed:Fire()
end

function Catalog.registerCurrency(def: Currency)
	assertUnsealed("currency", def.id)
	if currencies[def.id] ~= nil then
		warn(`[Store] currency "{def.id}" already registered; overwriting`)
	end
	currencies[def.id] = def
	Catalog.Changed:Fire()
end

function Catalog.registerProduct(def: Product)
	assertUnsealed("product", def.id)
	if products[def.id] ~= nil then
		warn(`[Store] product {def.id} already registered; overwriting`)
	end
	products[def.id] = def
	Catalog.Changed:Fire()
end

function Catalog.registerGamepass(def: Gamepass)
	assertUnsealed("gamepass", def.id)
	if gamepasses[def.id] ~= nil then
		warn(`[Store] gamepass {def.id} already registered; overwriting`)
	end
	gamepasses[def.id] = def
	Catalog.Changed:Fire()
end

function Catalog.registerInventoryTab(def: InventoryTab)
	if inventoryTabs[def.id] ~= nil then
		warn(`[Store] inventory tab "{def.id}" already registered; overwriting`)
	end
	inventoryTabs[def.id] = def
	Catalog.Changed:Fire()
end

-- Lookups ---------------------------------------------------------------------

function Catalog.getPack(id: string): Pack?
	return packs[id]
end

function Catalog.getCurrency(id: string): Currency?
	return currencies[id]
end

function Catalog.getProduct(id: number): Product?
	return products[id]
end

-- Listing ---------------------------------------------------------------------

local function byOrderThenName<T>(list: { any }): { any }
	table.sort(list, function(a, b)
		local ao = a.order or math.huge
		local bo = b.order or math.huge
		if ao ~= bo then
			return ao < bo
		end
		return a.name < b.name
	end)
	return list
end

-- Every pack of one kind, sorted. `kind = nil` returns all of them.
function Catalog.listPacks(kind: PackKind?): { Pack }
	local result: { Pack } = {}
	for _, pack in packs do
		if kind == nil or pack.kind == kind then
			table.insert(result, pack)
		end
	end
	return byOrderThenName(result) :: { Pack }
end

-- The kinds that actually have packs, sorted. A kind with nothing in it is a
-- feature that's installed but has no content yet — an empty tab is worse than
-- no tab, so it doesn't get one. A pack whose kind was never registered is the
-- reverse mistake and warns loudly rather than rendering under a blank heading.
function Catalog.listKinds(): { Kind }
	local populated: { [string]: boolean } = {}
	for _, pack in packs do
		if kinds[pack.kind] == nil then
			-- Once per pack, not once per render: this is called every time the
			-- shop's tab strip renders.
			if not warnedKinds[pack.id] then
				warnedKinds[pack.id] = true
				warn(`[Store] pack "{pack.id}" has unregistered kind "{pack.kind}"`)
			end
			continue
		end
		populated[pack.kind] = true
	end

	local result: { Kind } = {}
	for id in populated do
		table.insert(result, kinds[id])
	end
	table.sort(result, function(a, b)
		local ao = a.order or math.huge
		local bo = b.order or math.huge
		if ao ~= bo then
			return ao < bo
		end
		return a.title < b.title
	end)
	return result
end

function Catalog.getKind(id: PackKind): Kind?
	return kinds[id]
end

-- Every registered currency, sorted by name (they have no order field — there
-- are rarely more than one or two, and a stable alphabetical strip is enough).
function Catalog.listCurrencies(): { Currency }
	local result: { Currency } = {}
	for _, currency in currencies do
		table.insert(result, currency)
	end
	table.sort(result, function(a, b)
		return a.name < b.name
	end)
	return result
end

function Catalog.listProducts(group: ProductGroup): { Product }
	local result: { Product } = {}
	for _, product in products do
		if product.group == group then
			table.insert(result, product)
		end
	end
	return byOrderThenName(result) :: { Product }
end

function Catalog.listGamepasses(): { Gamepass }
	local result: { Gamepass } = {}
	for _, pass in gamepasses do
		table.insert(result, pass)
	end
	return byOrderThenName(result) :: { Gamepass }
end

function Catalog.listInventoryTabs(): { InventoryTab }
	local result: { InventoryTab } = {}
	for _, tab in inventoryTabs do
		table.insert(result, tab)
	end
	table.sort(result, function(a, b)
		local ao = a.order or math.huge
		local bo = b.order or math.huge
		if ao ~= bo then
			return ao < bo
		end
		return a.title < b.title
	end)
	return result
end

return Catalog
