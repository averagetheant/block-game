-- Purchase announcements in chat: "Someone bought Nuke!", in the general
-- channel, for everyone in the server.
--
-- The three action products are the ones the whole room feels — a tower gone, a
-- stage skipped, a minute back on everyone's clock — so the room is told who
-- did it. The server decides *that* a purchase happened (TowerProductsService,
-- only once the effect actually applied); this decides what it reads like,
-- because chat is a presentation and the wording doesn't belong on the wire.
--
-- Nothing here is TowerGame-specific beyond the packet: the product's name
-- comes out of the Store catalog, so renaming a product renames the
-- announcement and a fourth action product would need no edit here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)
local Packets = require(ReplicatedStorage.Features.TowerGame.Packets)
-- The shared catalog, populated on this realm by Store's auto-discovery loop —
-- the same one the shop reads its cards out of.
local StoreCatalog = require(ReplicatedStorage.Features.Store.Catalog)

local TowerAnnounceController = {}

-- The general channel, or nil on a place still running the legacy chat (where
-- TextChannels doesn't exist at all). Missing chat means no announcement, not
-- an error — the purchase already happened and its effect is on screen.
local function generalChannel(): TextChannel?
	local channels = TextChatService:FindFirstChild("TextChannels")
	if channels == nil then
		return nil
	end
	local channel = channels:FindFirstChild(Constants.ANNOUNCE_CHANNEL)
	return if channel and channel:IsA("TextChannel") then channel else nil
end

-- System messages are rich text, so a name goes through here before it's
-- interpolated into one. Display names can't currently contain markup, but the
-- escape is the difference between "can't today" and "can't" — an unescaped
-- name is a hole that opens the day Roblox widens the character set.
local function escaped(name: string): string
	local safe = string.gsub(name, "&", "&amp;")
	safe = string.gsub(safe, "<", "&lt;")
	safe = string.gsub(safe, ">", "&gt;")
	return safe
end

local function announce(productId: number, userId: number)
	local channel = generalChannel()
	if channel == nil then
		return
	end

	local product = StoreCatalog.getProduct(productId)
	if product == nil then
		return
	end

	-- Whoever bought it is in this server by definition — they were here a
	-- moment ago to click the prompt — but they can still have left between the
	-- purchase and the packet landing, and an announcement with a hole where the
	-- name goes is worse than none.
	local buyer = Players:GetPlayerByUserId(userId)
	if buyer == nil then
		return
	end

	channel:DisplaySystemMessage(
		`<font color="{Constants.ANNOUNCE_NAME_COLOR}">{escaped(buyer.DisplayName)}</font>`
			.. ` bought <b>{escaped(product.name)}</b>!`
	)
end

function TowerAnnounceController.Start()
	if not Constants.Presentations.actions then
		return
	end

	Packets.Announce.listen(function(payload)
		announce(payload.productId, payload.userId)
	end)
end

return TowerAnnounceController
