-- Auto-discovery file picked up by the ChatHints feature's `init.luau` loop.
-- Tips about the two windows this feature owns — the shop and the inventory.
-- Deliberately content-free: Store ships no packs, so neither do its hints.
--
-- Receives the ChatHints table as a parameter to avoid a circular require.

return function(ChatHints)
	ChatHints.registerHints({
		{
			id = "store.shop",
			order = 1,
			text = "Coins you earn are spent in the Shop, on the left rail.",
		},
		{
			id = "store.inventory",
			order = 2,
			text = "Anything you own is equipped from the Inventory window — including the skin your blocks are built out of.",
		},
	})
end
