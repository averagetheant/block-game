-- TowerGame's funnels. Discovered by src/features/Analytics/init.luau at load
-- time; see docs/game/Analytics.md.
--
-- Three of the experience's ten funnel slots, at three different time scales,
-- because "where do players fall off" has a different answer depending on how
-- far out you stand:
--
--   round    one run from fresh base to storm      → does a run finish
--   stage    one checkpoint's worth of climbing    → is the target fair
--   turn     one piece, handed to dropped          → do players understand it
--
-- (The fourth scale — a whole visit, in minutes — is the `session` funnel, and
-- it belongs to Analytics itself: its steps are elapsed time and it would read
-- the same in a game with no tower in it.)
--
-- The turn funnel is the only high-volume one in the game (a turn every ~15s
-- per player) and is sampled to a tenth. See Constants.TURN_SAMPLE_RATE.
--
-- Onboarding steps 2–4 are allocated here; Analytics owns 1 and Store owns 5–6.
-- The onboarding funnel is one funnel for the whole experience, so those
-- numbers are a shared space — the allocation table lives in
-- docs/game/Analytics.md and any new step goes on the end.

return function(Analytics)
	-- --------------------------------------------------------------- round --
	-- A round is fresh base → storm takes the tower. The interesting question
	-- is how deep a room gets before the storm wins, so the steps are
	-- checkpoints rather than time.
	Analytics.registerFunnel({
		id = "round",
		name = "Round Progress",
		scope = "One run, from the first piece to the storm. New session each round.",
		steps = {
			"Round Started",
			"First Piece Placed",
			"Checkpoint 1",
			"Checkpoint 2",
			"Checkpoint 3",
			"Checkpoint 5",
			"Checkpoint 10",
		},
	})

	-- --------------------------------------------------------------- stage --
	-- One checkpoint attempt, measured as fractions of the target height. This
	-- is the tuning funnel for STORM_FIRST_TARGET and STORM_GAP_GROWTH: a stage
	-- where most rooms reach 75% and then run out of clock is a stage whose
	-- target is a little too far out, and that's invisible in the round funnel.
	Analytics.registerFunnel({
		id = "stage",
		name = "Stage Attempt",
		scope = "One checkpoint attempt. New session each stage.",
		steps = {
			"Stage Started",
			"25% Height",
			"50% Height",
			"75% Height",
			"Cleared",
		},
	})

	-- ---------------------------------------------------------------- turn --
	-- One piece, from handed to settled. Sampled: see the note at the top.
	--
	-- The step worth watching is "Steered" — a turn that goes from handed
	-- straight to dropped without the player ever moving the piece is a player
	-- who doesn't know they can, and that's a tutorial problem rather than a
	-- difficulty one.
	Analytics.registerFunnel({
		id = "turn",
		name = "Turn Taken",
		scope = "One piece. New session each turn; sampled.",
		sampleRate = Analytics.Constants.TURN_SAMPLE_RATE,
		steps = {
			"Piece Received",
			"Steered",
			"Rotated",
			"Dropped",
			"Settled On Tower",
		},
	})

	-- ---------------------------------------------------------- onboarding --
	-- Steps 2–4: the three things that have to happen after arriving for a new
	-- player to have actually played the game, in the order they happen.
	Analytics.registerOnboardingStep({ step = 2, name = "First Turn" })
	Analytics.registerOnboardingStep({ step = 3, name = "First Block Placed" })
	Analytics.registerOnboardingStep({ step = 4, name = "First Checkpoint" })
end
