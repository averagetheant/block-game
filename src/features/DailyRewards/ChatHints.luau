-- Auto-discovery file picked up by the ChatHints feature's `init.luau` loop.
-- The daily run's own tips, owned by the feature that runs it.
--
-- Receives the ChatHints table as a parameter to avoid a circular require.
-- Loaded on both realms, so it reads tunables and nothing else.

return function(ChatHints)
	local Constants = require(script.Parent.Constants)

	ChatHints.registerHints({
		{
			id = "dailyrewards.claim",
			order = 1,
			text = `Claim your daily reward every day you play — {Constants.CYCLE_DAYS} days in a row and the last one is the grand prize.`,
		},
		{
			id = "dailyrewards.streak",
			order = 2,
			text = "Days roll over at UTC midnight, not 24 hours after your last claim. Miss one and the run starts again from day one.",
		},
	})
end
