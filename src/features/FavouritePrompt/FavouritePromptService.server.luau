-- Server half of FavouritePrompt: remembers that a player has been asked.
--
-- That's the whole job. The decision and the prompt are the client's (see the
-- controller for why); this writes the flag that makes "only once" survive a
-- rejoin.
--
-- The write is one-way — false → true, never back — so the packet needs no
-- payload and no rate limit: a client that spams it is asking to be marked as
-- prompted, which it already is.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Features.FavouritePrompt.Constants)
local Packets = require(ReplicatedStorage.Features.FavouritePrompt.Packets)
local PlayerDataService = require(ServerScriptService.Features.PlayerData.PlayerDataService)

local FavouritePromptService = {}

-- After PlayerData (1) so SetValue is ready. Nothing else waits on this one —
-- the first write is a whole round away.
FavouritePromptService.Priority = 10

local function wasAsked(player: Player): boolean?
	local data = PlayerDataService.GetData(player)
	if data == nil then
		return nil
	end
	local slice = data[Constants.PROFILE_KEY]
	if typeof(slice) ~= "table" then
		return nil
	end
	return slice.Prompted == true
end

-- The core intent: this player has now been asked, so don't ask again.
function FavouritePromptService.markAsked(player: Player)
	if wasAsked(player) ~= false then
		return
	end
	-- Blessed mutation path: replica diff + profile autosave stay in sync.
	PlayerDataService.SetValue(player, { Constants.PROFILE_KEY, "Prompted" }, true)
end

-- Puts the player back to never-asked, so the next vote asks again. Exists for
-- the `favouriteprompt` command — a once-per-account flow is otherwise a
-- one-shot to test, and you don't get a second account per attempt.
function FavouritePromptService.reset(player: Player): boolean
	if wasAsked(player) == nil then
		return false
	end
	PlayerDataService.SetValue(player, { Constants.PROFILE_KEY, "Prompted" }, false)
	return true
end

function FavouritePromptService.Start()
	Packets.Shown.listen(function(_, player)
		FavouritePromptService.markAsked(player)
	end)
end

return FavouritePromptService
