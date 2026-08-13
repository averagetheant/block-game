-- Store's slice of the PlayerData profile template. Discovered by
-- src/features/PlayerData/init.luau at load time; see docs/game/PlayerData.md.
--
-- Keep this to registration only — StoreService owns the reads and writes.
--
-- Note what *isn't* here: a balance. Currency lives in whichever feature earns
-- it (TowerGame's Cash), and Store debits it through the path that feature
-- registered. A second copy here would be a second source of truth.

return function(PlayerData)
	PlayerData.registerTemplate("Store", {
		-- packId → true. Absent means not owned; nothing is ever set to false,
		-- so a pack that leaves the catalog leaves no tombstone behind.
		Owned = {},
		-- pack kind → packId. One equipped pack per kind; absent means none,
		-- which is a legitimate choice ("no skin") rather than a missing value.
		Equipped = {},
		-- Robux receipt ids already granted, newest last. See
		-- Constants.MAX_RECEIPT_HISTORY.
		Receipts = {},
	})
end
