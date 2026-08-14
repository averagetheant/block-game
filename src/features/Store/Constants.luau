-- Shared config for Store — the shop, the inventory, and the ownership they
-- both read. Plain .luau => shipped to ReplicatedStorage, readable from any realm.

return {
	-- Top-level profile key this feature owns (registered in PlayerData.luau).
	PROFILE_KEY = "Store",

	-- UIShell frame ids. Other features can open either window with
	-- `UIShell.useFrame().open(Store.SHOP_FRAME_ID)`.
	SHOP_FRAME_ID = "Shop",
	INVENTORY_FRAME_ID = "Inventory",

	-- Longest pack id the server will even look up. A cheap bound on the string
	-- a client can make us hash.
	MAX_PACK_ID_LENGTH = 64,

	-- How many Robux receipts are remembered per profile. Roblox re-delivers a
	-- receipt until it's granted, so the ids are what stop a redelivery from
	-- paying twice; the cap keeps the profile from growing forever. Well past
	-- the number of purchases that could land inside one redelivery window.
	MAX_RECEIPT_HISTORY = 50,

	-- ------------------------------------------------------------------- ui --
	-- Pack / product card geometry. Three cards plus two gaps is what the
	-- default window width fits, so the row count is arithmetic rather than a
	-- measurement — change the window size and this needs changing with it.
	CARD_WIDTH = 236,
	-- Tall enough for four wrapped lines of description under the art. Three was
	-- not: the neon pack's copy was being cut off mid-sentence, and a shop card
	-- that can't finish its own sentence is worse than one with no copy at all.
	-- Tall enough that a body-tier description gets ~4 wrapped lines above the
	-- action button. Grow this before shrinking the description's text size —
	-- a card that can't finish its sentence is the failure this guards against.
	CARD_HEIGHT = 360,
	CARD_GAP = 14,
	CARD_ICON = 88,
	CARDS_PER_ROW = 3,
	-- Tab strip.
	TAB_HEIGHT = 54,
	TAB_TEXT_SIZE = 32,
	TAB_GAP = 8,
	-- Balance pill in the shop's top bar.
	BALANCE_WIDTH = 190,
	BALANCE_HEIGHT = 44,

	-- Which surfaces this feature renders. Flip one off to drop that surface
	-- without deleting code (see docs/game/presentations.md).
	Presentations = {
		shop = true,
		inventory = true,
	},
}
