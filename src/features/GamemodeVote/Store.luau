-- GamemodeVote's entry in the Store catalog. Discovered by
-- src/features/Store/init.luau at load time; see docs/game/Store.md.
--
-- One card, and a card is all this file is: what the pass *does* is weigh a
-- stamp double in the tally, and the tally is server code (GamemodeVoteService).
-- This module loads on both realms, so it can't hold it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local assets = require(ReplicatedStorage.Shared.Boil).assets
local Constants = require(script.Parent.Constants)

return function(Store)
	Store.registerGamepass({
		id = Constants.GAMEPASS_DOUBLE_VOTE,
		name = "2x Votes",
		description = `Your vote counts {Constants.DOUBLE_VOTE_WEIGHT}x when the room picks how the next round plays.`,
		icon = assets.Icons.friends,
		variant = "blue",
		order = 3,
	})
end
