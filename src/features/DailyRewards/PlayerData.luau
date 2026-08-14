-- DailyRewards' slice of the PlayerData profile template. Discovered by
-- src/features/PlayerData/init.luau at load time; see docs/game/PlayerData.md.
--
-- Keep this to registration only — DailyRewardsService owns the reads and
-- writes. Note what *isn't* here: what the player was given. The rewards
-- themselves land in whatever slice owns them (coins in TowerGame's, packs in
-- Store's); a copy here would be a second source of truth for the same coin.

return function(PlayerData)
	PlayerData.registerTemplate("DailyRewards", {
		-- Day of the run last claimed, 1..CYCLE_DAYS. Written as the day that
		-- was granted, so it wraps instead of growing forever. 0 = none yet.
		Streak = 0,
		-- os.time() of that claim; 0 = never. Only the UTC day of it is read
		-- (see Cycle.luau), but the full stamp is worth keeping for support
		-- questions and for any future "claimed at" display.
		LastClaim = 0,
	})
end
