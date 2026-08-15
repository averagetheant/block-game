--!strict
-- Tunables for the one-time "favourite this experience?" ask.
--
-- Everything here is about *when* the ask happens, not what it looks like — the
-- prompt is Roblox's own, drawn by the client, and the only thing this feature
-- gets to choose is the moment.

return {
	-- This feature's slice of the profile (see PlayerData.luau). Read on the
	-- client to decide whether to ask, written by the server once it has asked.
	PROFILE_KEY = "FavouritePrompt",

	-- Seconds between the ballot opening and the prompt appearing.
	--
	-- 0 puts it up with the panels, which is the moment the player's attention is
	-- free — nothing is being built and the round is over. It's also the version
	-- that costs a first-timer their first vote: Roblox's prompt is modal, and the
	-- poll only runs for GamemodeVote's VOTE_SECONDS (15). Push this past that
	-- (18 clears the clock and the result window both) to ask on the way into the
	-- round instead of over the ballot.
	PROMPT_DELAY = 0,

	-- Which presentations are active. There's no screen — the prompt *is* the
	-- screen and it's Roblox's — and no world part.
	Presentations = {
		-- `favouriteprompt` clears the flag so the next vote asks again. Without
		-- it this flow happens once per account, ever, which is untestable.
		command = true,
	},
}
