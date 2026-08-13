-- Server side of the shop: the only place a price is read, a balance is
-- debited, or ownership is granted. The client sends what it wants; everything
-- about whether it can have it happens here.
--
-- It also owns `MarketplaceService.ProcessReceipt`, because Roblox allows
-- exactly one callback per game. Currency products are granted straight from
-- the catalog (grant `amount` of `currency`); anything else — a nuke, a stage
-- skip — is a handler the owning feature registers with
-- `StoreService.registerProductHandler`, so Store never learns what a nuke is.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Required for its side effect: loading Features.Store runs init.luau's
-- auto-discovery loop, which registers every feature's packs, currencies and
-- products into the per-realm catalog. Submodule requires (Constants, Catalog)
-- do NOT trigger it, so without this line the server's catalog stays empty and
-- every purchase is rejected.
require(ReplicatedStorage.Features.Store)

local Constants = require(ReplicatedStorage.Features.Store.Constants)
local Catalog = require(ReplicatedStorage.Features.Store.Catalog)
local Packets = require(ReplicatedStorage.Features.Store.Packets)
local PlayerDataService = require(ServerScriptService.Features.PlayerData.PlayerDataService)

local StoreService = {}

-- After PlayerData (1), ahead of the feature services that register product
-- handlers — a receipt that lands before its handler is registered comes back
-- as NotProcessedYet and Roblox re-delivers it, so the ordering is a nicety
-- rather than a correctness requirement.
StoreService.Priority = 10

local KEY = Constants.PROFILE_KEY

-- productId → handler. Populated by feature services at Start.
local productHandlers: { [number]: (player: Player) -> boolean } = {}

-- Reading + writing another feature's currency ------------------------------

local function slice(player: Player): { [string]: any }?
	local data = PlayerDataService.GetData(player)
	return if data then data[KEY] else nil
end

-- Walks a registered currency's profile path. Returns nil when the profile
-- hasn't loaded or the path doesn't resolve — a currency whose owning feature
-- isn't installed shouldn't crash a purchase, it should decline it.
local function readBalance(player: Player, currencyId: string): number?
	local currency = Catalog.getCurrency(currencyId)
	if currency == nil then
		return nil
	end
	local node: any = PlayerDataService.GetData(player)
	for _, step in currency.path do
		if typeof(node) ~= "table" then
			return nil
		end
		node = node[step]
	end
	return if typeof(node) == "number" then node else nil
end

local function writeBalance(player: Player, currencyId: string, value: number): boolean
	local currency = Catalog.getCurrency(currencyId)
	if currency == nil then
		return false
	end
	return PlayerDataService.SetValue(player, currency.path, value)
end

-- Public API ------------------------------------------------------------------

function StoreService.getBalance(player: Player, currencyId: string): number
	return readBalance(player, currencyId) or 0
end

-- Credit a player. Used by the Robux currency products and available to any
-- feature that wants to pay out through the same path.
function StoreService.credit(player: Player, currencyId: string, amount: number): boolean
	if amount <= 0 then
		return false
	end
	local balance = readBalance(player, currencyId)
	if balance == nil then
		return false
	end
	return writeBalance(player, currencyId, balance + amount)
end

function StoreService.owns(player: Player, packId: string): boolean
	local saved = slice(player)
	local owned = if saved then saved.Owned else nil
	return typeof(owned) == "table" and owned[packId] == true
end

-- Register what a non-currency developer product actually does. The handler
-- returns true when the effect was applied; false means "not now" and the
-- receipt is left for Roblox to re-deliver rather than being eaten.
function StoreService.registerProductHandler(productId: number, handler: (player: Player) -> boolean)
	if productHandlers[productId] ~= nil then
		warn(`[Store] product handler {productId} already registered; overwriting`)
	end
	productHandlers[productId] = handler
end

-- Purchases -------------------------------------------------------------------

local function grant(player: Player, packId: string)
	PlayerDataService.SetValue(player, { KEY, "Owned", packId }, true)
end

local function onPurchase(payload: { packId: string }, player: Player)
	local packId = payload.packId
	if #packId == 0 or #packId > Constants.MAX_PACK_ID_LENGTH then
		return
	end

	local pack = Catalog.getPack(packId)
	if pack == nil then
		warn(`[Store] {player.Name} tried to buy unregistered pack "{packId}"`)
		return
	end
	if StoreService.owns(player, packId) then
		return
	end

	local balance = readBalance(player, pack.currency)
	if balance == nil then
		warn(`[Store] pack "{packId}" priced in unregistered currency "{pack.currency}"`)
		return
	end
	if balance < pack.price then
		return
	end

	-- Debit first: if the grant somehow fails the player is out the money but
	-- can buy again, which is recoverable. The other order hands out free packs.
	if not writeBalance(player, pack.currency, balance - pack.price) then
		return
	end
	grant(player, packId)
end

local function onEquip(payload: { kind: string, packId: string }, player: Player)
	local packId = payload.packId
	if #packId > Constants.MAX_PACK_ID_LENGTH or #payload.kind > Constants.MAX_PACK_ID_LENGTH then
		return
	end

	-- Empty id = unequip. Nothing to validate beyond the kind being a string,
	-- and clearing a slot that was already clear is harmless.
	if #packId == 0 then
		PlayerDataService.SetValue(player, { KEY, "Equipped", payload.kind }, nil)
		return
	end

	local pack = Catalog.getPack(packId)
	if pack == nil then
		warn(`[Store] {player.Name} tried to equip unregistered pack "{packId}"`)
		return
	end
	if pack.kind ~= payload.kind then
		warn(`[Store] {player.Name} sent pack "{packId}" for the wrong kind "{payload.kind}"`)
		return
	end
	if not StoreService.owns(player, packId) then
		warn(`[Store] {player.Name} tried to equip unowned pack "{packId}"`)
		return
	end

	PlayerDataService.SetValue(player, { KEY, "Equipped", pack.kind }, packId)
end

-- Robux receipts --------------------------------------------------------------

-- Roblox re-delivers a receipt until it's acknowledged as granted, so the
-- purchase id has to be remembered or a redelivery pays twice. The list is
-- capped: the oldest ids fall off, long after any redelivery window.
local function alreadyGranted(player: Player, purchaseId: string): boolean
	local saved = slice(player)
	local receipts = if saved then saved.Receipts else nil
	if typeof(receipts) ~= "table" then
		return false
	end
	return table.find(receipts, purchaseId) ~= nil
end

local function rememberReceipt(player: Player, purchaseId: string)
	local saved = slice(player)
	local receipts = if saved and typeof(saved.Receipts) == "table" then table.clone(saved.Receipts) else {}
	table.insert(receipts, purchaseId)
	while #receipts > Constants.MAX_RECEIPT_HISTORY do
		table.remove(receipts, 1)
	end
	PlayerDataService.SetValue(player, { KEY, "Receipts" }, receipts)
end

local function processReceipt(info: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(info.PlayerId)
	-- They left mid-purchase. Not granted, so don't acknowledge it — Roblox
	-- re-delivers when they next join.
	if player == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local purchaseId = tostring(info.PurchaseId)
	if alreadyGranted(player, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	-- The profile isn't loaded yet: granting now would write into nothing and
	-- the money would vanish. Leave it for the redelivery.
	if slice(player) == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local product = Catalog.getProduct(info.ProductId)
	if product == nil then
		warn(`[Store] receipt for unregistered product {info.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local granted: boolean
	if product.group == "currency" then
		granted = StoreService.credit(player, product.currency or "", product.amount or 0)
	else
		local handler = productHandlers[product.id]
		if handler == nil then
			warn(`[Store] product {product.id} ("{product.name}") has no registered handler`)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local ok, result = pcall(handler, player)
		if not ok then
			warn(`[Store] product handler {product.id} errored: {result}`)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		granted = result == true
	end

	if not granted then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	rememberReceipt(player, purchaseId)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function StoreService.Start()
	Packets.Purchase.listen(onPurchase)
	Packets.Equip.listen(onEquip)

	-- One callback per game, and this is it. A second feature assigning
	-- ProcessReceipt would silently replace this one and every purchase Store
	-- knows about would stop being granted — register a handler instead.
	MarketplaceService.ProcessReceipt = processReceipt
end

return StoreService
