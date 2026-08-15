-- Client core for FavouritePrompt: asks a player to favourite the experience,
-- once, at the first gamemode vote they ever see.
--
-- Why the vote and not the join: a player who has been in the game for eleven
-- seconds has no opinion about it yet, and the loading screen is the worst
-- possible moment to put a modal in front of. The round break is the one beat
-- where nothing is being built, the tower they just played is still on screen,
-- and the game is already asking them a question.
--
-- Why the client owns the decision: `AvatarEditorService` is a client service,
-- and "the ballot reached this player's screen" is a client fact — the server
-- opens a poll for a server, not for a person. The server's half is one write.

local AvatarEditorService = game:GetService("AvatarEditorService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Features.FavouritePrompt.Constants)
local Packets = require(ReplicatedStorage.Features.FavouritePrompt.Packets)

-- Client-realm siblings (StarterPlayerScripts.Features.*).
--
-- Both are hard requires: without PlayerData there's nothing to remember the ask
-- in, and without GamemodeVote there's no moment to make it at. See
-- docs/game/FavouritePrompt.md § The dependencies.
local PlayerDataController = require(script.Parent.Parent.PlayerData.PlayerDataController)
local GamemodeVoteController = require(script.Parent.Parent.GamemodeVote.GamemodeVoteController)

local FavouritePromptController = {}

-- Session guard, on top of the persisted flag. The profile write is a round trip
-- away and PROMPT_DELAY can outlast a poll, so between scheduling the prompt and
-- the replica diff coming back there's a window where the flag still reads false
-- and another ballot could open in it.
local asked = false

-- Whether this player has already been asked, or `nil` while the profile hasn't
-- arrived — which is a different answer from "no" and gets treated as one.
local function wasAsked(): boolean?
	local data = PlayerDataController.GetData()
	if data == nil then
		return nil
	end
	local slice = data[Constants.PROFILE_KEY]
	if typeof(slice) ~= "table" then
		return nil
	end
	return slice.Prompted == true
end

-- The one intent. Puts Roblox's favourite prompt on screen and tells the server
-- it happened.
--
-- `PromptSetFavorite` throws rather than returning a result when the place can't
-- be favourited (an unpublished place in Studio is the one you'll hit), so the
-- report is sent only if the prompt actually went up — a throw here would
-- otherwise burn the player's one ask on a prompt they never saw. The session
-- guard stays set either way: whatever makes this fail is a property of the
-- place, not of the moment, so retrying at the next vote would only warn again.
function FavouritePromptController.prompt()
	local ok, err = pcall(function()
		AvatarEditorService:PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset, true)
	end)
	if not ok then
		warn(`[FavouritePrompt] couldn't prompt: {err}`)
		return
	end

	Packets.Shown.send()
end

-- A ballot just opened on this player's screen.
--
-- `nil` from wasAsked is "the profile hasn't landed yet" and skips this poll
-- rather than guessing. It only happens to someone who joined seconds before a
-- round ended, and the cost of guessing wrong in either direction (asking a
-- returning player again, or spending the ask silently) is worse than waiting
-- for the next vote.
local function onBallotOpened()
	if asked or wasAsked() ~= false then
		return
	end

	-- Set before the delay, not inside it: the whole point of the guard is the
	-- window between scheduling and the profile catching up.
	asked = true
	task.delay(Constants.PROMPT_DELAY, FavouritePromptController.prompt)
end

function FavouritePromptController.Start()
	-- The vote's state goes out on change, and `endsAt ~= 0` is what "a poll is
	-- up" means on the wire (see docs/game/GamemodeVote.md § Packets). The edge is
	-- what matters — every stamp anyone lands re-fires this.
	local showing = GamemodeVoteController.isActive()

	GamemodeVoteController.DataChanged:Connect(function(state)
		local open = state.endsAt ~= 0
		if open and not showing then
			onBallotOpened()
		end
		showing = open
	end)

	-- The flag going true → false under us is the `favouriteprompt` command
	-- resetting it, and the session guard has to go with it or the reset would
	-- need a rejoin to take effect. Watched as an edge rather than "is it false
	-- now": any *other* profile write during the window between prompting and
	-- the server's write landing would otherwise clear the guard, which is the
	-- one thing the guard is there to prevent.
	local persisted = wasAsked() == true

	PlayerDataController.DataChanged:Connect(function()
		local now = wasAsked()
		if now == nil then
			return
		end
		if persisted and not now then
			asked = false
		end
		persisted = now
	end)
end

return FavouritePromptController
