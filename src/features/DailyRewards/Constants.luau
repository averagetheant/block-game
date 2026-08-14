-- Shared config for DailyRewards. Plain .luau => shipped to ReplicatedStorage,
-- readable from any realm (the client renders against it, the server validates
-- against it, and they must agree).

return {
	-- Top-level profile key this feature owns (registered in PlayerData.luau).
	PROFILE_KEY = "DailyRewards",

	-- UIShell frame id. Another feature can send the player here with
	-- `UIShell.useFrame().open(DailyRewards.FRAME_ID)`.
	FRAME_ID = "DailyRewards",

	-- Days in one run. The last day is the grand prize and gets the tall card;
	-- everything before it is a square in the grid. Change this and the UI
	-- follows — the grid derives its rows from the count.
	CYCLE_DAYS = 7,
	-- Squares per row in the grid of non-grand days.
	COLUMNS = 3,

	-- How many *missed* days end a run. 1 = the normal rule: claim on
	-- consecutive days or start over. Raise it to forgive a lapse (2 = one day
	-- off is fine). The day boundary is UTC midnight — see Cycle.luau for why
	-- that and not "24h since your last claim".
	GRACE_DAYS = 1,

	-- A claim the server won't even look up. A cheap bound on a hostile client.
	MAX_DAY = 64,

	-- ------------------------------------------------------------------- ui --
	-- Card geometry, in pixels against the 1280x720 reference. The window sizes
	-- itself from these (see WINDOW_SIZE), so bumping a card resizes the frame
	-- rather than clipping it.
	-- 240 is the size the layout was tuned at, but the shipped window also has
	-- to hold a footer strip and the Window's own chrome inside the 1280x720
	-- reference — 220 keeps the whole frame under ~1025x606, with margin.
	SQUARE_SIZE = 220,
	GRAND_WIDTH = 300,
	-- Gap between cards, and the inset from the window edge to the grid. One
	-- value for both so the border reads the same as the gutter.
	CARD_GAP = 15,
	-- Bottom row of a card: the Claim / Claimed / Day N button.
	ACTION_HEIGHT = 46,
	GRAND_ACTION_HEIGHT = 56,
	-- Gap between rows inside a card. Smaller than CARD_GAP on purpose: a
	-- card's rows are one object, and spacing them as far apart as two
	-- neighbouring cards would dissolve it.
	CARD_ROW_GAP = 6,
	GRAND_ROW_GAP = 10,
	-- Height of the countdown strip under the cards.
	FOOTER_HEIGHT = 52,

	-- How often the countdown re-renders. One second: it counts down in hours
	-- and minutes, so anything finer just burns renders.
	COUNTDOWN_TICK = 1,

	-- The feature's icon: the TopbarPlus button and the window's title badge use
	-- the same art, so the thing you click and the thing that opens are visibly
	-- one object.
	ICON = "rbxassetid://79189310973071",
	-- Where the icon sits on the topbar (TopbarPlus sorts left-aligned icons by
	-- this, low → high).
	TOPBAR_ORDER = 1,
	-- Window title badge.
	TITLE = "Daily Rewards",
	TITLE_VARIANT = "yellow",

	-- Which surfaces this feature renders. Flip one off to drop that surface
	-- without deleting code (see docs/game/presentations.md).
	--
	-- `window` is the frame itself; without it the topbar button would open
	-- nothing. This feature mounts its own UIShell.Frame + Window rather than
	-- registering a screen for the Sidebar rail to host, because its entry
	-- point is the topbar and the rail only renders windows for rail entries.
	Presentations = {
		window = true,
		topbar = true,
		command = true,
	},
}
