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

	-- The claim button's pulse: how far it swells, and how long one breath takes.
	-- A button that sits still is a button a new player reads as a label — the
	-- run is worth nothing to somebody who never presses it. Sine both ways so
	-- it breathes rather than ticks, and small enough that six locked days beside
	-- it don't start to shimmer by association.
	PULSE_SCALE = 1.07,
	PULSE_SECONDS = 0.6,

	-- ------------------------------------------------------------- the prompt --
	-- The nudge a player gets on joining with a reward waiting: the window opens
	-- itself, and everything behind it goes dark so the only lit thing on screen
	-- is the card with the live Claim button. See DailyRewardsPrompt.
	--
	-- How dark. Enough that the HUD reads as switched off, short of hiding it —
	-- the game is still there, it's just not the thing to look at.
	SCRIM_COLOR = Color3.fromRGB(0, 0, 0),
	SCRIM_TRANSPARENCY = 0.45,
	SCRIM_FADE_SECONDS = 0.25,

	-- Stacking inside the feature's own root: the scrim under the window, the
	-- notice over it. The root's own layer (`ui.layers.window`) is what puts the
	-- whole set above the HUD; these three only sort each other.
	SCRIM_ZINDEX = 1,
	WINDOW_ZINDEX = 2,
	NOTICE_ZINDEX = 3,

	-- After the last waiting reward is claimed: how long the window stays up, and
	-- how long the notice outlives it. The window goes first so the last thing on
	-- screen is the sentence that says when to come back.
	CLOSE_SECONDS = 3,
	NOTICE_SECONDS = 5,
	NOTICE_TEXT = "Come back tomorrow for your next daily reward!",
	NOTICE_WIDTH = 620,
	NOTICE_HEIGHT = 84,

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
