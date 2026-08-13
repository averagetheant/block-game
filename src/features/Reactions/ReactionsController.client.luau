-- Client surface for Reactions. Exposes the two intents (send one, rearrange
-- the bar) plus the reads the views need, and re-broadcasts incoming reactions
-- as a signal the float layer subscribes to.
--
-- It applies nothing locally: the bar's contents come back as a replica diff,
-- and even your own reaction is drawn from the server's Play broadcast — so
-- what you see is exactly what everyone else sees.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Packages.Signal)

local Catalog = require(ReplicatedStorage.Features.Reactions.Catalog)
local Constants = require(ReplicatedStorage.Features.Reactions.Constants)
local Packets = require(ReplicatedStorage.Features.Reactions.Packets)

-- Client-realm sibling controllers.
local PlayerDataController = require(script.Parent.Parent.PlayerData.PlayerDataController)
local StoreController = require(script.Parent.Parent.Store.StoreController)

local ReactionsController = {}

-- Fires with (reactionId, userId) every time anyone reacts, the local player
-- included. The float layer is the only subscriber today.
ReactionsController.Played = Signal.new()

local KEY = Constants.PROFILE_KEY

-- Reads -----------------------------------------------------------------------

function ReactionsController.owns(reactionId: string): boolean
	local reaction = Catalog.get(reactionId)
	if reaction == nil then
		return false
	end
	if reaction.pack == nil then
		return true
	end
	return StoreController.owns(reaction.pack)
end

-- The bar's contents. Always exactly SLOT_COUNT entries: a slot the profile
-- doesn't have (or holds a reaction that no longer exists) falls back to the
-- default for that position, so the bar can't render a hole.
function ReactionsController.slots(): { string }
	local data = PlayerDataController.GetData()
	local saved = if data then data[KEY] else nil
	local stored = if saved then saved.Slots else nil

	local result: { string } = {}
	for index = 1, Constants.SLOT_COUNT do
		local id = if typeof(stored) == "table" then stored[index] else nil
		if typeof(id) ~= "string" or Catalog.get(id) == nil then
			id = Catalog.DEFAULT_SLOTS[index] or Catalog.DEFAULT_SLOTS[1]
		end
		result[index] = id
	end
	return result
end

-- Intents ---------------------------------------------------------------------

function ReactionsController.send(reactionId: string)
	if typeof(reactionId) ~= "string" or #reactionId == 0 then
		return
	end
	Packets.Send.send({ reactionId = reactionId })
end

-- Put `reactionId` in slot `index`, leaving the rest as they are. The whole
-- list goes up (see Packets.luau) so the server validates one coherent bar.
function ReactionsController.setSlot(index: number, reactionId: string)
	if typeof(index) ~= "number" or index < 1 or index > Constants.SLOT_COUNT then
		return
	end
	if not ReactionsController.owns(reactionId) then
		return
	end

	local slots = ReactionsController.slots()
	slots[index] = reactionId
	Packets.SetSlots.send({ slots = slots })
end

function ReactionsController.Start()
	Packets.Play.listen(function(payload: { reactionId: string, userId: number })
		-- A reaction from a pack this client hasn't loaded a definition for is
		-- dropped rather than drawn as a blank — the catalog is shared, so this
		-- only happens across a version skew.
		if Catalog.get(payload.reactionId) == nil then
			return
		end
		ReactionsController.Played:Fire(payload.reactionId, payload.userId)
	end)
end

return ReactionsController
