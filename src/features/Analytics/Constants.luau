-- Shared config for Analytics.
--
-- The numbers here are mostly Roblox's, not ours: the funnel cap, the step
-- range and the custom-field count are platform limits, and exceeding one
-- doesn't error — it silently stops showing up on the dashboard, which is the
-- worst failure mode telemetry can have. Registry checks against them at
-- registration time so a bad funnel is a load-time warn instead of a month of
-- missing data.

return {
	-- ------------------------------------------------------------- platform --
	-- Roblox renders at most ten funnel tabs on the analytics dashboard, and
	-- ignores funnels past that. The onboarding funnel is NOT one of the ten:
	-- it's a separate API (LogOnboardingFunnelStepEvent) with its own tab.
	MAX_FUNNELS = 10,
	-- Steps are 1-based and cap at 100.
	MIN_STEP = 1,
	MAX_STEP = 100,
	-- Three custom fields per event, keyed CustomField01..03. The keys are
	-- literal strings on the wire — `Enum.AnalyticsCustomFieldKeys.CustomField01.Name`
	-- evaluates to "CustomField01" — so they're spelled out rather than read off
	-- the enum, which keeps this file loadable on a client that has no reason to
	-- touch AnalyticsService.
	CUSTOM_FIELD_KEYS = { "CustomField01", "CustomField02", "CustomField03" },
	MAX_CUSTOM_FIELDS = 3,

	-- ------------------------------------------------------------ sampling --
	-- Per-turn telemetry is the one genuinely high-volume funnel in the game: a
	-- turn every ~15s per player, so a full ten-player server produces roughly
	-- 160 step events a minute from the Turn funnel alone. Conversion rates
	-- don't need every turn — they need enough turns — so the funnel is sampled
	-- per turn and the dashboard reads the same shape at a tenth the volume.
	--
	-- Sampling is decided once per funnel *session*, never per step: a coin flip
	-- at each step would drop step 3 of a session whose step 2 was kept, which
	-- reads on the dashboard as players abandoning mid-funnel.
	TURN_SAMPLE_RATE = 0.1,
	-- Everything else is low enough volume to log whole. 1 = log everything.
	DEFAULT_SAMPLE_RATE = 1,

	-- ------------------------------------------------------------- economy --
	-- Transaction types are plain strings on this API (not an enum value), and
	-- Roblox counts at most 20 unique ones per experience. These are the six the
	-- game actually has.
	TRANSACTION = {
		-- Coins paid out by play: zone bonus, height, the idle tick.
		GAMEPLAY = "Gameplay",
		-- Coins bought with Robux.
		IAP = "IAP",
		-- Coins and packs handed over by the daily run.
		TIMED_REWARD = "TimedReward",
		-- Coins spent in the shop.
		SHOP = "Shop",
		-- A Robux product bought from a rail button mid-round rather than from
		-- the shop — Roblox's own name for exactly this.
		CONTEXTUAL = "ContextualPurchase",
		-- Cmdr's `givecash`. Kept distinct so a dev testing in a live place
		-- doesn't quietly pollute the earn curve.
		ADMIN = "Admin",
	},
	-- Roblox allows five currency types per experience. We have one.
	CURRENCY_COINS = "coins",

	-- ---------------------------------------------------------- progression --
	-- Checkpoints are the game's levels: reaching one is a Complete, the storm
	-- taking the tower is a Fail. One path name, because there's one climb.
	PROGRESSION_PATH = "TowerClimb",

	-- ------------------------------------------------------------ throttle --
	-- A hard ceiling on events per player per minute, counted across every
	-- funnel. Nothing in the game should come close; this exists so that a bug
	-- (a step fired from inside a render, a loop that re-enters) costs a warn
	-- and some dropped events rather than the experience's entire analytics
	-- quota for the day.
	MAX_EVENTS_PER_MINUTE = 120,

	-- Which surfaces this feature runs. Off = no telemetry leaves the server,
	-- and every `step` call becomes a no-op — the call sites stay put.
	Presentations = {
		-- The server logger. The single switch that turns the feature off.
		service = true,
		-- Client-reported steps (a window opening, a card being clicked). These
		-- are things the server genuinely cannot see; the packet is the only way
		-- they reach the dashboard.
		client = true,
	},
}
