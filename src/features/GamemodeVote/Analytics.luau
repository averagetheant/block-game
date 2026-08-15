-- GamemodeVote's funnel. Discovered by src/features/Analytics/init.luau at load
-- time; see docs/game/Analytics.md.
--
-- The last of the experience's ten funnel slots. It measures participation
-- rather than money: the vote is a fifteen-second window in which every player
-- is asked to press one of three panels, and the fraction who don't is the
-- clearest read available on how many people in a server are actually still at
-- the keyboard.
--
-- That makes this funnel do double duty as an AFK gauge, which is why "Round
-- Started" is a step. Players who voted and then didn't place a block in the
-- round they voted for are a different problem from players who never voted.

return function(Analytics)
	Analytics.registerFunnel({
		id = "vote",
		name = "Gamemode Vote",
		scope = "One poll, between rounds.",
		steps = {
			"Vote Opened",
			"Ballot Shown",
			"Vote Cast",
			"Result Shown",
			"Round Started",
		},
	})
end
