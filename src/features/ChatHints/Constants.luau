--!strict
-- Tunables for ChatHints — the rotating tip line in chat.
--
-- The cadence numbers are the whole feature's personality: often enough that a
-- player who joined mid-round learns the rules without asking, rare enough that
-- the general channel stays theirs. Five minutes is one hint per storm stage —
-- TowerGame's `STORM_SECONDS` is 300 — so a tip lands about once per run rather
-- than twice, and the channel stays quiet enough that a hint still reads as
-- worth looking at.

return {
	-- Seconds between hints. Every client runs its own clock (a system message
	-- is local to the player who sees it), so two players who joined a minute
	-- apart read their hints a minute apart — which is the point: the rotation
	-- is paced to *your* session, not the server's uptime.
	INTERVAL_SECONDS = 300,

	-- Seconds from the controller starting to the first hint. Not zero: the
	-- first thing a joining player sees should be the game, and a tip that lands
	-- while the place is still streaming in scrolls past unread. One minute is
	-- long enough to have taken a turn and short enough that the first hint is
	-- still about the thing they just did.
	FIRST_HINT_SECONDS = 60,

	-- Which channel the hints go to. The default general channel — the one
	-- everyone already has open, and the same one TowerGame announces purchases
	-- in.
	CHANNEL = "RBXGeneral",

	-- How long to wait for TextChatService to build its channels before giving
	-- up. Chat is created a moment after the client boots; a place still running
	-- the legacy chat never creates it at all, and that's a silent no-op (the
	-- game is playable without tips), not an error.
	CHANNEL_WAIT_SECONDS = 15,

	-- The label in front of every hint, and its rich-text colour. Coloured so
	-- the eye can tell a hint from a player line at a glance without reading it.
	PREFIX = "Tip",
	PREFIX_COLOR = "#7dd3ff",
	-- The hint body. Slightly dimmer than chat's white so the tips read as the
	-- room's furniture rather than someone talking.
	TEXT_COLOR = "#dfe7ef",

	-- Which surfaces this feature renders. Off = the hints stop and every
	-- registration stays where it is, code intact.
	Presentations = {
		chat = true,
	},
}
