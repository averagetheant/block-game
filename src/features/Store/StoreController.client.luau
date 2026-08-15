-- Client surface for Store. Reads ownership, equipped slots and balances off
-- the PlayerData replica, and sends intents up. It never applies a purchase
-- locally — the replica diff coming back is the source of truth, so a rejected
-- request simply never changes anything rather than flickering.
--
-- Robux purchases don't go through a packet at all: MarketplaceService's prompt
-- is a client call, and the grant arrives on the server as a receipt.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Required for its side effect: see StoreService.server.luau. Submodule
-- requires alone don't trigger Store/init.luau, so the catalog would be empty.
require(ReplicatedStorage.Features.Store)

local Constants = require(ReplicatedStorage.Features.Store.Constants)
local Catalog = require(ReplicatedStorage.Features.Store.Catalog)
local Packets = require(ReplicatedStorage.Features.Store.Packets)
local Signal = require(ReplicatedStorage.Packages.Signal)
local audio = require(ReplicatedStorage.Shared.Boil).audio

-- Client-realm sibling controllers.
local PlayerDataController = require(script.Parent.Parent.PlayerData.PlayerDataController)
-- Telemetry for the half of the purchase journey the server can't see: which
-- card was clicked, and whether a prompt was ever asked for. Reported from here
-- rather than from ShopUI so the views stay dumb — see docs/game/headless-core.md.
local AnalyticsController = require(script.Parent.Parent.Analytics.AnalyticsController)

local StoreController = {}

local KEY = Constants.PROFILE_KEY

local function slice(): { [string]: any }?
	local data = PlayerDataController.GetData()
	return if data then data[KEY] else nil
end

-- Reads -----------------------------------------------------------------------

function StoreController.owns(packId: string): boolean
	local saved = slice()
	local owned = if saved then saved.Owned else nil
	return typeof(owned) == "table" and owned[packId] == true
end

-- The pack equipped in `kind`'s slot, or nil for none. Nil is a real answer
-- here, not a missing one: "no skin" is a choice.
function StoreController.equipped(kind: string): string?
	local saved = slice()
	local map = if saved then saved.Equipped else nil
	if typeof(map) ~= "table" then
		return nil
	end
	local packId = map[kind]
	return if typeof(packId) == "string" then packId else nil
end

-- Balance of a registered currency, wherever on the profile its owning feature
-- keeps it. Zero when the replica hasn't arrived or the currency isn't known —
-- a UI that renders "0" while data loads is better than one that renders nil.
function StoreController.balance(currencyId: string): number
	local currency = Catalog.getCurrency(currencyId)
	if currency == nil then
		return 0
	end
	local node: any = PlayerDataController.GetData()
	for _, step in currency.path do
		if typeof(node) ~= "table" then
			return 0
		end
		node = node[step]
	end
	return if typeof(node) == "number" then node else 0
end

-- Gamepass ownership, asked of Roblox rather than read off the replica: it isn't
-- ours to store, and what the client learns here only decides between a Buy
-- button and an Owned badge. Everything a pass actually *does* is checked again
-- on the server (StoreService.ownsGamepass) — a client saying "I own it" is not
-- a grant.
--
-- Answers arrive a moment after join, so the shop re-renders off the signal
-- rather than reading once at mount.
StoreController.GamepassesChanged = Signal.new()

local gamepassOwned: { [number]: boolean } = {}

function StoreController.ownsGamepass(gamepassId: number): boolean
	return gamepassOwned[gamepassId] == true
end

local function setGamepassOwned(gamepassId: number, owns: boolean)
	if gamepassOwned[gamepassId] == owns then
		return
	end
	gamepassOwned[gamepassId] = owns
	StoreController.GamepassesChanged:Fire()
end

local function refreshGamepass(gamepassId: number)
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(Players.LocalPlayer.UserId, gamepassId)
	end)
	if not ok then
		warn(`[Store] gamepass {gamepassId} ownership check failed: {owns}`)
		return
	end
	setGamepassOwned(gamepassId, owns == true)
end

function StoreController.canAfford(packId: string): boolean
	local pack = Catalog.getPack(packId)
	if pack == nil then
		return false
	end
	return StoreController.balance(pack.currency) >= pack.price
end

-- Intents ---------------------------------------------------------------------

function StoreController.purchase(packId: string)
	if typeof(packId) ~= "string" or #packId == 0 then
		return
	end
	-- The click, as distinct from the server's "Purchase Sent" — which is the
	-- same event one hop later. Both exist because the hop can fail: a card that
	-- reports Pack Selected and never reaches Purchase Sent is a packet that
	-- didn't land, and that looks nothing like a player who couldn't afford it.
	AnalyticsController.step("shop", "Pack Selected")
	Packets.Purchase.send({ packId = packId })
end

function StoreController.equip(kind: string, packId: string)
	if typeof(kind) ~= "string" or typeof(packId) ~= "string" then
		return
	end
	-- Only a real equip gets the cue; the empty id is `unequip`, and taking
	-- something off shouldn't sound like putting it on.
	if #packId > 0 then
		audio.playUI("equip")
		-- Unequipping isn't the end of the equip funnel; it's the opposite of it.
		AnalyticsController.step("inventory", "Pack Equipped")
	end
	Packets.Equip.send({ kind = kind, packId = packId })
end

-- Empty id is the wire's "nothing equipped"; see Packets.luau.
function StoreController.unequip(kind: string)
	StoreController.equip(kind, "")
end

function StoreController.promptProduct(productId: number)
	-- A product still on its 0 placeholder until the real one is configured on
	-- the place. Prompting with it throws, so decline politely — and say so,
	-- the way promptGamepass does: a button that does nothing at all is
	-- indistinguishable from a broken one when you're testing in Studio.
	if typeof(productId) ~= "number" or productId <= 0 then
		warn("[Store] product has no id yet; set one on its registration to enable the button")
		return
	end
	-- A step, not a new session. The product funnel's session is opened when the
	-- shop opens ("Product Shown"), because that's the population this is a
	-- conversion *of* — starting a session here instead would mean every row in
	-- the funnel began at step 2 and the drop-off from seeing to clicking, the
	-- thing worth knowing, would never appear.
	AnalyticsController.step("product", "Prompt Requested")
	MarketplaceService:PromptProductPurchase(Players.LocalPlayer, productId)
end

function StoreController.promptGamepass(gamepassId: number)
	-- A placeholder gamepass carries id 0 until the real one is configured.
	-- Prompting with it throws, so decline politely instead.
	if typeof(gamepassId) ~= "number" or gamepassId <= 0 then
		warn("[Store] gamepass has no id yet; set one on its registration to enable the button")
		return
	end
	-- A step for the same reason as promptProduct above.
	AnalyticsController.step("gamepass", "Prompt Requested")
	MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, gamepassId)
end

function StoreController.Start()
	-- One query per registered pass, spawned so a slow web call doesn't hold up
	-- the rest of the client's startup. Id 0 is a placeholder card and asking
	-- about it throws.
	for _, pass in Catalog.listGamepasses() do
		if pass.id > 0 then
			task.spawn(refreshGamepass, pass.id)
		end
	end

	-- A pass bought mid-session: the prompt closing is the only notice Roblox
	-- gives, and the card behind it is still showing "Buy".
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(_, gamepassId, wasPurchased)
		if not wasPurchased then
			return
		end
		audio.playUI("purchase")
		setGamepassOwned(gamepassId, true)
	end)

	-- The purchase cue fires on the *grant*, not the request. Playing it when
	-- the packet goes up would chime for a purchase the server then declined —
	-- and this file's whole premise is that the replica coming back is the only
	-- thing that means anything. Watching the owned set also covers Robux
	-- products, which never send a packet at all.
	--
	-- The first payload is the profile loading, not a purchase, so the baseline
	-- is taken before anything can sound.
	local known: { [string]: boolean }? = nil

	PlayerDataController.DataChanged:Connect(function()
		local saved = slice()
		local owned = if saved then saved.Owned else nil
		if typeof(owned) ~= "table" then
			return
		end

		if known == nil then
			known = table.clone(owned)
			return
		end

		for packId, isOwned in owned do
			if isOwned == true and (known :: any)[packId] ~= true then
				audio.playUI("purchase")
				break
			end
		end
		known = table.clone(owned)
	end)
end

return StoreController
