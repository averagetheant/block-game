-- Root presentation for Sidebar: the left rail is always on screen, so it
-- registers as a root element rather than into a frame slot. Discovered +
-- required by init.client.luau before the root mounts; registration is the only
-- side effect.
--
-- Nothing about *what's on* the rail happens here — the rail reads the registry
-- at render, and features fill that registry from their own files.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local UIRegistry = require(ReplicatedStorage.Shared.Boil).UIRegistry
local Constants = require(ReplicatedStorage.Features.Sidebar.Constants)
local SidebarRail = require(ReplicatedStorage.Features.Sidebar.SidebarRail)

if Constants.Presentations.root then
	UIRegistry.registerRoot("Sidebar", React.createElement(SidebarRail))
end

return {}
