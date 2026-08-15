-- Auto-discovery file picked up by the Settings feature's `init.luau` loop.
-- Registers the "Not playing" toggle (which takes a player out of the turn queue
-- without making them leave the server), the landing preview, and the Music
-- toggle that gates TowerMusicController's zone playlist.
--
-- Receives the Settings table as a parameter to avoid a circular require —
-- this file never imports Features.Settings directly.

return function(Settings)
	local Constants = require(script.Parent.Constants)

	-- Registered here as well as in the Music feature, because either can be the
	-- one installed. Only one of them registers at a time: Music's registration
	-- is gated on its controller actually running.
	Settings.registerCategory({
		id = "audio",
		title = "Audio",
		order = 1,
	})

	Settings.registerSetting({
		kind = "toggle",
		id = Constants.SETTING_MUSIC,
		label = "Music",
		category = "audio",
		default = true,
		order = 1,
		variant = "blue",
	})

	Settings.registerCategory({
		id = "gameplay",
		title = "Gameplay",
		order = 3,
	})

	Settings.registerSetting({
		kind = "toggle",
		id = Constants.SETTING_NOT_PLAYING,
		label = "Not playing",
		category = "gameplay",
		default = false,
		order = 1,
		variant = "red",
	})

	Settings.registerSetting({
		kind = "toggle",
		id = Constants.SETTING_LANDING_PREVIEW,
		label = "Landing preview",
		category = "gameplay",
		default = true,
		order = 2,
		variant = "green",
	})

	-- Registered for everyone so both realms agree the id exists (the server
	-- validates writes against that), but only *shown* to players who own the
	-- Double Turn gamepass — that gate is set in TowerSettingsPresentation, which
	-- is client-only because ownership is a MarketplaceService answer.
	Settings.registerSetting({
		kind = "toggle",
		id = Constants.SETTING_DOUBLE_TURN,
		label = "Double Turn",
		category = "gameplay",
		default = true,
		order = 3,
		variant = "purple",
	})
end
