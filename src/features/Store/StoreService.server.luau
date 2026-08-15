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

-- Telemetry. This service is where every purchase in the game actually
-- completes, so it owns the closing step of all three purchase funnels and the
-- sink side of the economy. See docs/game/Analytics.md.
local AnalyticsService = require(ServerScriptService.Features.Analytics.AnalyticsService)
local AnalyticsConstants = require(ReplicatedStorage.Features.Analytics.Constants)

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

-- The pack equipped in `kind`'s slot, or nil for none. The server-side mirror of
-- StoreController.equipped, for features whose cosmetic has to be applied
-- authoritatively — a skin everyone in the room can see is a server decision,
-- not something each client paints for itself.
function StoreService.equipped(player: Player, kind: string): string?
	local saved = slice(player)
	local map = if saved then saved.Equipped else nil
	if typeof(map) ~= "table" then
		return nil
	end
	local packId = map[kind]
	return if typeof(packId) == "string" and #packId > 0 then packId else nil
end

-- Gamepasses ------------------------------------------------------------------

-- Ownership is Roblox's answer, so it's asked for rather than stored: every
-- registered pass is queried once when a player joins, and again when a purchase
-- prompt closes over one. Nothing goes on the profile — a refunded pass has to
-- stop working, and a profile would remember it forever.
--
-- player -> gamepassId -> owns.
local gamepassOwned: { [Player]: { [number]: boolean } } = {}

local function queryGamepass(player: Player, gamepassId: number)
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamepassId)
	end)
	if not ok then
		warn(`[Store] gamepass {gamepassId} ownership check failed for {player.Name}: {owns}`)
		return
	end
	local owned = gamepassOwned[player]
	-- They left while the call was out.
	if owned == nil then
		return
	end
	owned[gamepassId] = owns == true
end

local function trackGamepasses(player: Player)
	gamepassOwned[player] = {}
	for _, pass in Catalog.listGamepasses() do
		-- Id 0 is a placeholder card (see StoreController.promptGamepass); asking
		-- Roblox about it throws.
		if pass.id <= 0 then
			continue
		end
		task.spawn(queryGamepass, player, pass.id)
	end
end

-- Whether `player` owns a gamepass. Deliberately non-yielding: this is read from
-- gameplay code (a cash award, a turn handed out), and a web call in the middle
-- of a turn is not something the game can wait on. The cost is that a pass reads
-- as unowned for the moment between joining and the query landing — the safe
-- direction to be wrong in, and the passes in the game are per-turn or per-award
-- rather than one-shot.
function StoreService.ownsGamepass(player: Player, gamepassId: number): boolean
	local owned = gamepassOwned[player]
	return owned ~= nil and owned[gamepassId] == true
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

-- Mark a pack owned, no payment involved. Public because buying is not the only
-- way a pack can arrive — a daily reward, a promo, an admin grant — and every
-- one of those should write ownership through the same line rather than
-- reaching into the profile itself.
--
-- Declines an unregistered pack: ownership of something no catalog describes is
-- a row nothing can ever render or equip.
function StoreService.grantPack(player: Player, packId: string): boolean
	if typeof(packId) ~= "string" or #packId == 0 or #packId > Constants.MAX_PACK_ID_LENGTH then
		return false
	end
	if Catalog.getPack(packId) == nil then
		warn(`[Store] refusing to grant unregistered pack "{packId}"`)
		return false
	end
	-- Already owned counts as success: the caller asked for the player to have
	-- it, and they do. A daily reward shouldn't fail (and stay claimable) just
	-- because the pack was bought yesterday.
	if StoreService.owns(player, packId) then
		return true
	end

	local granted = PlayerDataService.SetValue(player, { KEY, "Owned", packId }, true)
	if granted then
		-- Onboarding step 6, fired here rather than in `onPurchase` so it counts
		-- however the pack arrived. A player whose first pack was a daily reward
		-- has still reached "owns something", and the funnel is about the player
		-- getting there, not about the till.
		AnalyticsService.onboarding(player, 6)
	end
	return granted
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
	-- The shop never draws a card for one of these, so this is a crafted packet
	-- rather than a mis-click. It's the whole guarantee behind a reward-only
	-- pack: the only way to it is the thing that grants it.
	if not Catalog.forSale(pack) then
		warn(`[Store] {player.Name} tried to buy pack "{packId}", which isn't for sale`)
		return
	end
	if StoreService.owns(player, packId) then
		return
	end

	-- Logged before the affordability check, not after. This step is "the
	-- player asked to buy something", and the gap between it and "Pack Granted"
	-- is the players who wanted a pack and couldn't afford it — which is the
	-- single most useful number the shop produces, and it disappears entirely
	-- if the step only fires on success.
	AnalyticsService.step(player, "shop", "Purchase Sent", { pack.kind })

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
	local remaining = balance - pack.price
	if not writeBalance(player, pack.currency, remaining) then
		return
	end
	if not StoreService.grantPack(player, packId) then
		return
	end

	AnalyticsService.step(player, "shop", "Pack Granted", { pack.kind })
	AnalyticsService.economy(
		player,
		"sink",
		pack.price,
		remaining,
		AnalyticsConstants.TRANSACTION.SHOP,
		packId
	)
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

	AnalyticsService.step(player, "product", "Receipt Granted", { product.name })
	-- Coins bought with Robux enter the economy here rather than through
	-- CashService: `StoreService.credit` is a different write path, and it's the
	-- right one — these coins are a purchase, not earnings, and lumping them in
	-- with the gameplay taps would make the earn curve look twice as generous as
	-- it is.
	if product.group == "currency" then
		AnalyticsService.economy(
			player,
			"source",
			product.amount or 0,
			StoreService.getBalance(player, product.currency or ""),
			AnalyticsConstants.TRANSACTION.IAP,
			product.name
		)
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function StoreService.Start()
	Packets.Purchase.listen(onPurchase)
	Packets.Equip.listen(onEquip)

	-- One callback per game, and this is it. A second feature assigning
	-- ProcessReceipt would silently replace this one and every purchase Store
	-- knows about would stop being granted — register a handler instead.
	MarketplaceService.ProcessReceipt = processReceipt

	for _, player in Players:GetPlayers() do
		trackGamepasses(player)
	end
	Players.PlayerAdded:Connect(trackGamepasses)
	Players.PlayerRemoving:Connect(function(player)
		gamepassOwned[player] = nil
	end)

	-- A pass bought mid-session has to start working now, not next join. The
	-- prompt closing is the only notice Roblox gives.
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamepassId, wasPurchased)
		-- Fired whether or not they paid, which is what makes the gap between
		-- this step and "Pass Owned" a cancel rate rather than a mystery.
		AnalyticsService.step(player, "gamepass", "Prompt Closed", { tostring(gamepassId) })
		if not wasPurchased then
			return
		end
		AnalyticsService.step(player, "gamepass", "Pass Owned", { tostring(gamepassId) })

		local owned = gamepassOwned[player]
		if owned == nil then
			return
		end
		owned[gamepassId] = true
	end)

	-- The same beat for developer products. Nothing is granted here — that's
	-- ProcessReceipt's job and it may arrive later or not at all — so this only
	-- reports. Roblox hands this one a user id rather than a Player.
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, isPurchased)
		local player = Players:GetPlayerByUserId(userId)
		if player == nil then
			return
		end
		local product = Catalog.getProduct(productId)
		AnalyticsService.step(player, "product", "Prompt Closed", {
			if product then product.name else tostring(productId),
			if isPurchased then "Paid" else "Cancelled",
		})
	end)
end

return StoreService
