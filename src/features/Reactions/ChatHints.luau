-- Auto-discovery file picked up by the ChatHints feature's `init.luau` loop.
-- Tips about the reaction bar, owned by the feature that draws it.
--
-- Receives the ChatHints table as a parameter to avoid a circular require.

return function(ChatHints)
	ChatHints.registerHints({
		{
			id = "reactions.send",
			order = 1,
			text = "Tap a reaction on the right edge of the screen and the whole server sees it — the arrow tab slides the bar out of the way.",
		},
		{
			id = "reactions.swap",
			order = 2,
			text = "Reactions you own can be swapped into the bar from the Reactions tab of your Inventory.",
		},
	})
end
