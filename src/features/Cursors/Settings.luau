-- Auto-discovery file picked up by the Settings feature's `init.luau` loop.
-- Registers the toggle that hides everyone else's cursors.
--
-- Receives the Settings table as a parameter to avoid a circular require — this
-- file never imports Features.Settings directly.
--
-- It declares the "interface" category it needs rather than assuming one exists,
-- the same way Music declares "audio". Note that a second feature declaring the
-- same category id warns and overwrites — if one appears, the two declarations
-- have to agree on title and order.

return function(Settings)
	local Constants = require(script.Parent.Constants)

	Settings.registerCategory({
		id = "interface",
		title = "Interface",
		order = 2,
	})

	Settings.registerSetting({
		kind = "toggle",
		id = Constants.SETTING_ID,
		label = "Player cursors",
		category = "interface",
		default = true,
		order = 1,
		variant = "purple",
	})
end
