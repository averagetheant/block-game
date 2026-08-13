-- Shared config for Cursors — the live pointers every player leaves on the play
-- plane. Plain .luau => shipped to ReplicatedStorage, readable from any realm.
--
-- Cursors are positioned in **world space on the play plane**, not in screen
-- space. Screen space isn't shared: a phone and an ultrawide disagree about
-- where "the middle of the screen" is, so a screen-space cursor would point at
-- nothing on anyone else's monitor. A point on the plane is the same point for
-- everyone, and it's the space the game is already played in.

return {
	-- How often a client tells the server where its cursor is. Cursors are
	-- ambient, not competitive — nobody loses a turn because a pointer was 60ms
	-- stale — so this is deliberately far below frame rate.
	SEND_INTERVAL = 1 / 12,
	-- Movement below this (in studs, on the plane) isn't worth a packet.
	SEND_EPSILON = 0.15,

	-- Bounds a reported position is clamped into, server-side. A cursor is a
	-- cosmetic, and a cosmetic must not be a way to draw on the sky — these are
	-- generous around the play area and nothing more.
	LIMIT_X = 90,
	MIN_Y = -50,
	MAX_Y = 600,

	-- Drop a cursor that hasn't reported in this long. Covers a player who
	-- alt-tabbed, went to a menu, or turned cursors off — their pointer stops
	-- rather than hanging wherever they left it.
	STALE_SECONDS = 3,

	-- ------------------------------------------------------------ the drawing --
	-- Cursor image size, in studs on the plane. Small on purpose: this is a
	-- presence cue, not a pointer you aim with.
	SIZE = 2.2,
	-- Cursors sit in front of the tower so they're never buried inside it.
	PLANE_OFFSET_Z = 6,
	-- Semi-transparent — a dozen opaque arrows over the tower would be a mess.
	TRANSPARENCY = 0.35,
	NAME_TRANSPARENCY = 0.45,
	-- The name under the cursor, as a height in studs. Very small: it identifies
	-- a pointer you're already looking at, it isn't a label to read across the
	-- arena. The text is `TextScaled` into this band rather than given a pixel
	-- size, so it shrinks with distance the way the arrow does.
	NAME_HEIGHT = 1,
	-- How quickly a remote cursor catches up to its last reported position. The
	-- reports arrive at SEND_INTERVAL; this smooths between them so a cursor
	-- glides instead of stepping.
	FOLLOW_RATE = 18,

	-- ------------------------------------------------------------- the colours --
	-- Every player gets one, rolled from their user id so it's stable across a
	-- rejoin and identical on every client without being sent.
	SATURATION = 0.72,
	VALUE = 1,

	-- ------------------------------------------------------------------ touch --
	-- Mobile has no hover: the cursor follows a finger that's held down, and
	-- stops when it lifts. Movement under this many pixels doesn't count as a
	-- drag, so a tap on a HUD button doesn't fling the cursor across the arena.
	TOUCH_DRAG_THRESHOLD = 2,

	-- ---------------------------------------------------------------- gamepad --
	-- Console drives the cursor with the right stick, in studs per second at full
	-- deflection, and ignores the stick's resting jitter below DEADZONE.
	STICK_SPEED = 42,
	STICK_DEADZONE = 0.18,

	-- Setting id (registered in Settings.luau). Turning it off hides everyone
	-- else's cursors *and* stops this client reporting its own — a player who
	-- opted out of the feature shouldn't still be broadcasting into it.
	SETTING_ID = "cursors.enabled",

	-- Which surfaces this feature renders. Flip one off to drop that surface
	-- without deleting code (see docs/game/presentations.md).
	Presentations = {
		-- The world-space cursors themselves.
		world = true,
	},
}
