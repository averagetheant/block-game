-- Shared config for VoiceChat — server-wide voice plus the "who's talking"
-- readout in the bottom-left. Plain .luau => ReplicatedStorage, both realms.
--
-- The routing here is *deliberately* not Roblox's default. Default voice wires
-- each speaker's microphone into an AudioEmitter on their character and mixes it
-- against an AudioListener on your camera, so how well you hear someone depends
-- on how close they are. This feature bypasses that: every microphone is wired
-- straight into every listener's output, at full volume, with no position in it
-- at all. Everyone hears everyone, everywhere.
--
-- That only holds while `VoiceChatService.EnableDefaultVoice` is **false** — see
-- docs/game/VoiceChat.md. With it on, the default proximity graph runs *as well*
-- as this one and anyone nearby is heard twice.

return {
	-- ------------------------------------------------------------- the routing --
	-- Name the server gives an AudioDeviceInput it creates for a player. Only
	-- used when one isn't there already: with default voice on, the engine makes
	-- its own (named "AudioDeviceInput") and we adopt that rather than adding a
	-- second microphone for the same person.
	INPUT_NAME = "VoiceInput",
	-- How the server waits out VoiceChatService's place settings, which throw on
	-- read until the service has initialized — after the first players have
	-- already joined. Twenty quarter-second tries is five seconds of patience;
	-- in practice it answers on the first or second.
	SETTING_ATTEMPTS = 20,
	SETTING_RETRY_SECONDS = 0.25,
	-- The client's own mixdown, and the folder its wires live in. Both are local
	-- instances — the audio graph past the microphone is per-listener, so none of
	-- it needs to (or should) replicate.
	OUTPUT_NAME = "VoiceChatOutput",
	GRAPH_NAME = "VoiceChatGraph",

	-- --------------------------------------------------------- who's speaking --
	-- Microphone loudness (AudioAnalyzer RmsLevel, 0-1) that counts as speech.
	-- Low, because RMS over a speech window sits well under the peak — this is
	-- the floor between "breathing near the mic" and "talking".
	SPEAKING_RMS = 0.01,
	-- Keep showing someone for this long after they drop below the floor. Speech
	-- is full of gaps — between words, between sentences — and without a hold the
	-- chip flickers on and off several times per sentence.
	HOLD_SECONDS = 0.4,
	-- How often the analyzers are sampled. The list only changes when someone
	-- starts or stops, so this doesn't need to be per-frame; the ring animation
	-- smooths between samples.
	POLL_INTERVAL = 1 / 15,
	-- RMS that reads as "full" on the ring. Normal speech peaks well below 1, so
	-- the ring would barely move if it were scaled against the raw range.
	LEVEL_FULL = 0.08,
	-- How quickly the ring catches up to the sampled level, per second. High
	-- enough to feel live, low enough that it doesn't strobe on consonants.
	LEVEL_FOLLOW = 14,

	-- -------------------------------------------------------------- the chips --
	-- A chip is a headshot and a name over the world — no panel behind it. It's
	-- an ambient presence cue that comes and goes on its own, and a surface for
	-- each one would put a stack of boxes in the corner for something nobody
	-- interacts with. Its height is the avatar's; the width is what the name
	-- gets to run to.
	CHIP_WIDTH = 240,
	CHIP_HEIGHT = 32,
	CHIP_GAP = 6,
	AVATAR_SIZE = 32,
	-- Ring around the avatar, at rest and at full level. With no panel to frame
	-- it, this is the whole of "live" — and the only outline in the widget.
	RING_MIN = 2,
	RING_MAX = 5,
	RING_COLOR = Color3.fromRGB(96, 255, 148),
	-- Names longer than this are cut with an ellipsis. A chip is a glance, not a
	-- profile — and Roblox display names run to 20 characters.
	NAME_MAX_CHARS = 16,
	-- Most chips shown at once; past this the column reports a count instead.
	-- A hundred-player server can have a lot of people talking, and a list that
	-- grows without limit walks off the top of the screen.
	MAX_SHOWN = 4,

	-- ------------------------------------------------------------ the corner --
	-- The HUD's own edge margin, and how far the column is inset from the left.
	EDGE_MARGIN = 20,
	-- Distance from the bottom — right down in the corner, below the sidebar
	-- rail, so the chips stack in the dead space under it rather than across it.
	-- Low enough that the controls hint shares the corner for its first few
	-- seconds; the hint fades on its own, and the chips only appear while
	-- somebody is actually talking.
	BOTTOM_OFFSET = 24,
	-- Above the HUD and the reaction floats: the chips are small, and something
	-- drifting past shouldn't hide who is talking.
	Z_INDEX = 4,

	-- Which surfaces this feature renders. Flip one off to drop that surface
	-- without deleting code (see docs/game/presentations.md).
	Presentations = {
		-- The speaker chips in the bottom-left corner. Off = voice still works
		-- server-wide, it just isn't drawn.
		screen = true,
	},
}
