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
	})
end
