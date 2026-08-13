-- Shared config for Reactions — the bottom bar and the emojis it throws up the
-- screen. Plain .luau => shipped to ReplicatedStorage, readable from any realm.

return {
	-- Top-level profile key this feature owns (registered in PlayerData.luau).
	PROFILE_KEY = "Reactions",

	-- How many reactions the bar holds. The profile stores exactly this many
	-- slot ids; changing the number is safe (Reconcile fills, the bar clamps).
	SLOT_COUNT = 4,

	-- Longest reaction id the server will look up — a cheap bound on what a
	-- client can make us hash.
	MAX_REACTION_ID_LENGTH = 64,
	-- Minimum seconds between one player's reactions. The whole server sees
	-- every one of these, so the rate limit is the difference between a reaction
	-- and a screen full of confetti. Low enough to spam a little on purpose —
	-- FLOAT_MAX is what actually protects the screen.
	SEND_COOLDOWN = 0.2,

	-- -------------------------------------------------------------- the bar --
	-- Square side of one reaction button.
	BUTTON_SIZE = 40,
	BUTTON_GAP = 6,
	-- Inner padding between the bar's edge and its buttons.
	BAR_PADDING = 7,
	-- Corner radius on the bar and its buttons. Generous — it's what makes it
	-- read as minimal rather than as a plain rectangle.
	BAR_CORNER = 12,
	BUTTON_CORNER = 9,
	-- The arrow tab that opens the bar. Sits above the bar's top edge when
	-- closed and rides up with it when open.
	HANDLE_WIDTH = 48,
	HANDLE_HEIGHT = 18,
	-- Emoji glyph size inside a bar button. Kept to GLYPH_FIT of the button —
	-- see that constant for why it isn't simply the button size.
	GLYPH_TEXT_SIZE = 23,
	-- Fraction of a button an image reaction fills, so an image and an emoji
	-- read at the same weight.
	GLYPH_IMAGE_SCALE = 0.66,
	-- The most of a container an emoji's *text size* may take up. Emoji render
	-- taller than their nominal TextSize (ascenders, and the colour bitmap's own
	-- padding), so a glyph sized to its box gets its top and bottom shaved off
	-- wherever the parent clips — which the float's CanvasGroup always does.
	-- Every glyph size here is derived against this rather than eyeballed.
	GLYPH_FIT = 0.58,
	-- Open/close slide.
	SLIDE_TWEEN_INFO = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),

	-- The bar's palette. Deliberately not the gem look — see ReactionBar.ui.luau.
	BAR_COLOR = Color3.fromRGB(255, 255, 255),
	BAR_TRANSPARENCY = 0.04,
	BUTTON_COLOR = Color3.fromRGB(242, 244, 249),
	BUTTON_HOVER_COLOR = Color3.fromRGB(226, 231, 242),
	OUTLINE_COLOR = Color3.fromRGB(214, 219, 230),
	OUTLINE_THICKNESS = 1,
	ARROW_COLOR = Color3.fromRGB(96, 104, 122),

	-- ------------------------------------------------------------- the float --
	-- How long one reaction lives on screen, and how far up it travels (as a
	-- fraction of screen height).
	FLOAT_SECONDS = 2.4,
	FLOAT_RISE = 0.55,
	-- Where it starts, measured up from the bottom edge (scale). Just above the
	-- bar so a reaction doesn't launch out of the middle of the button.
	FLOAT_START_Y = 0.88,
	-- Horizontal spread around center (scale), rolled per reaction so a burst
	-- fans out instead of stacking into one column.
	FLOAT_SPREAD = 0.18,
	-- Sideways drift over the flight, rolled per reaction (scale).
	FLOAT_DRIFT = 0.06,
	FLOAT_SIZE = 44,
	FLOAT_TEXT_SIZE = 25,
	-- Cap on simultaneous floats. A full server all reacting at once is the
	-- case this exists for; past this the oldest is dropped.
	FLOAT_MAX = 24,

	-- Which surfaces this feature renders. Flip one off to drop that surface
	-- without deleting code (see docs/game/presentations.md).
	Presentations = {
		-- The bar + the float layer.
		bar = true,
		-- The Reactions tab inside the Store's inventory window.
		inventory = true,
	},
}
