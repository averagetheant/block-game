-- Screen presentation for Settings: registers the Settings window content into
-- the HUD's frame slot, and the native-topbar button that opens it. Discovered
-- + required by init.client.luau before the root mounts; registration is the
-- only side effect.
--
-- The two go in differently on purpose. The window content is a *screen*: the
-- Sidebar rail renders a window for the rail entry and mounts this inside it.
-- The topbar button is a *root*: it's not window content, it must be mounted
-- whether or not any frame is open, and being in the root tree is what puts it
-- inside FrameProvider. See docs/game/presentations.md.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local UIRegistry = require(ReplicatedStorage.Shared.Boil).UIRegistry
local Settings = require(ReplicatedStorage.Features.Settings)
local Constants = require(ReplicatedStorage.Features.Settings.Constants)

-- Client-realm siblings (StarterPlayerScripts.Features.Settings.…).
local SettingsView = require(script.Parent.SettingsView)
local SettingsTopbar = require(script.Parent.SettingsTopbar)

if Constants.Presentations.screen then
	UIRegistry.registerScreen(Settings.FRAME_ID, React.createElement(SettingsView))
end

if Constants.Presentations.topbar then
	UIRegistry.registerRoot("SettingsTopbar", React.createElement(SettingsTopbar))
end

return {}
