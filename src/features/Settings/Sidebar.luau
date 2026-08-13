-- Settings' entry on the left rail. Discovered by src/features/Sidebar/init.luau
-- at load time; see docs/game/Sidebar.md.
--
-- Declarative only — it names the UIShell frame to open, and the window's
-- *contents* arrive separately from SettingsPresentation. That's what lets this
-- file load on both realms: there's nothing client-only in it, and it requires
-- Constants rather than `Features.Settings` (whose init pulls in the React UI).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local assets = require(ReplicatedStorage.Shared.Boil).assets
local Constants = require(script.Parent.Constants)

return function(Sidebar)
	if not Constants.Presentations.sidebar then
		return
	end

	Sidebar.registerEntry({
		id = "Settings",
		label = "Settings",
		icon = assets.Icons.settings,
		frameId = Constants.FRAME_ID,
		titleVariant = "purple",
		-- Below Shop (1) and Bag (2): the things you open to play come first.
		order = 3,
	})
end
