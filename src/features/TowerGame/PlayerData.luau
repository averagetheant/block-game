-- TowerGame's slice of the PlayerData profile template. Discovered by
-- src/features/PlayerData/init.luau at load time; see docs/game/PlayerData.md.
--
-- Keep this to registration only — TowerStatsService owns the reads and writes.

return function(PlayerData)
	PlayerData.registerTemplate("TowerGame", {
		-- Pieces this player has dropped, across every session.
		BlocksPlaced = 0,
		-- The tallest the shared tower has ever been while they were in it.
		BiggestHeight = 0,
		-- Earned by reaching zones and by time played. See CashService.
		Cash = 0,
		-- Whether the "Not playing" setting was turned on *for* this player by
		-- the inactivity check rather than by them.
		--
		-- The setting itself is a preference and persists, which is right for a
		-- player who chose it and a trap for one who was away: they would come
		-- back tomorrow already benched, never get a turn, and have no reason to
		-- connect the two. TowerService clears both on join when this is set, so
		-- being idle costs a player the rest of that session at most.
		AutoAfk = false,
		-- Whether this player has ever been in the server when a checkpoint
		-- cleared. It's what qualifies them for the first-checkpoint quest (see
		-- CheckpointQuestService and CheckpointQuest.ui) — the rare skin is handed
		-- over on the clear and this flag is what closes the quest behind it, so
		-- the prize can only ever be earned once.
		SeenCheckpoint = false,
	})
end
