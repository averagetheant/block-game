-- Server side of reactions: the only place that decides whether a reaction is
-- real, whether the sender owns it, and whether they're allowed to send it yet.
--
-- Everything here exists because a reaction is a *broadcast*. An unvalidated
-- one is a client drawing on everyone else's screen, and an unthrottled one is
-- a client doing it sixty times a second.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Catalog = require(ReplicatedStorage.Features.Reactions.Catalog)
local Constants = require(ReplicatedStorage.Features.Reactions.Constants)
local Packets = require(ReplicatedStorage.Features.Reactions.Packets)
local PlayerDataService = require(ServerScriptService.Features.PlayerData.PlayerDataService)
local StoreService = require(ServerScriptService.Features.Store.StoreService)

local ReactionsService = {}

-- After PlayerData (1) and Store (10) — ownership is a Store read.
ReactionsService.Priority = 15

local KEY = Constants.PROFILE_KEY

-- player → os.clock() of their last accepted reaction.
local lastSent: { [Player]: number } = {}

-- A reaction is usable when it's free, or when its pack has been bought.
local function canUse(player: Player, reactionId: string): boolean
	if #reactionId == 0 or #reactionId > Constants.MAX_REACTION_ID_LENGTH then
		return false
	end
	local reaction = Catalog.get(reactionId)
	if reaction == nil then
		return false
	end
	if reaction.pack == nil then
		return true
	end
	return StoreService.owns(player, reaction.pack)
end

local function onSend(payload: { reactionId: string }, player: Player)
	local now = os.clock()
	local last = lastSent[player]
	if last ~= nil and now - last < Constants.SEND_COOLDOWN then
		return
	end

	if not canUse(player, payload.reactionId) then
		return
	end

	lastSent[player] = now
	Packets.Play.sendToAll({ reactionId = payload.reactionId, userId = player.UserId })
end

local function onSetSlots(payload: { slots: { string } }, player: Player)
	local slots = payload.slots
	if typeof(slots) ~= "table" or #slots ~= Constants.SLOT_COUNT then
		return
	end

	-- Every slot has to be a reaction they can actually use. Rejecting the
	-- whole list rather than sanitising it keeps the client's view and the
	-- profile identical — a half-applied write is a bar that lies.
	for _, reactionId in slots do
		if typeof(reactionId) ~= "string" or not canUse(player, reactionId) then
			warn(`[Reactions] {player.Name} sent an unusable slot list`)
			return
		end
	end

	PlayerDataService.SetValue(player, { KEY, "Slots" }, table.clone(slots))
end

function ReactionsService.Start()
	Packets.Send.listen(onSend)
	Packets.SetSlots.listen(onSetSlots)

	Players.PlayerRemoving:Connect(function(player)
		lastSent[player] = nil
	end)
end

return ReactionsService
