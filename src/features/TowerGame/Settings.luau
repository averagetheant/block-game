-- Auto-discovery file picked up by the Settings feature's `init.luau` loop.
-- Registers the "Not playing" toggle, which takes a player out of the turn
-- queue without making them leave the server.
--
-- Receives the Settings table as a parameter to avoid a circular require —
-- this file never imports Features.Settings directly.

return function(Settings)
	local Constants = require(script.Parent.Constants)

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
end
