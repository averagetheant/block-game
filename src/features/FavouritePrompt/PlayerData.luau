-- FavouritePrompt's slice of the PlayerData profile template. Discovered by
-- src/features/PlayerData/init.luau at load time; see docs/game/PlayerData.md.
--
-- One flag, and it's on the profile rather than in memory because "only once"
-- means once per *player*, not once per session. A session-local guard would ask
-- again every time they rejoined, which is the version of this that gets a game
-- reported rather than favourited.

return function(PlayerData)
	local Constants = require(script.Parent.Constants)

	PlayerData.registerTemplate(Constants.PROFILE_KEY, {
		-- Whether this player has ever been asked. Records the *ask*, not the
		-- answer: Roblox tells us how the prompt closed but a "no" is still an
		-- answer, and asking a second time would be nagging.
		Prompted = false,
	})
end
