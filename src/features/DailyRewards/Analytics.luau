-- DailyRewards' funnel. Discovered by src/features/Analytics/init.luau at load
-- time; see docs/game/Analytics.md.
--
-- One of the experience's ten funnel slots, and the one whose steps are least
-- about a single sitting: a daily run is a `CYCLE_DAYS`-long journey, and the
-- thing worth knowing is which day people stop coming back on.
--
-- So this funnel is deliberately shaped as *days of the run*, not as clicks
-- within one visit. The clicks are worth two steps at the front (a player who
-- opens the window and doesn't claim is a broken button, and that has to be
-- distinguishable from a player who never opened it) and after that every step
-- is a day.
--
-- The funnel session therefore spans days rather than minutes, keyed by the run
-- rather than generated fresh — see DailyRewardsService, which passes the run's
-- start date as the session id. That's the `<playerId>-<itemId>` pattern from
-- Roblox's own guidance for funnels that outlive a session.

return function(Analytics)
	Analytics.registerFunnel({
		id = "daily",
		name = "Daily Rewards",
		scope = "One run through the daily cycle. Session id is the run's start date.",
		steps = {
			"Reward Available",
			"Window Opened",
			"Day 1 Claimed",
			"Day 2 Claimed",
			"Day 3 Claimed",
			"Day 4 Claimed",
			"Day 5 Claimed",
			"Day 6 Claimed",
			"Grand Prize Claimed",
		},
	})
end
