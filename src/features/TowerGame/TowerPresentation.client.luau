-- Root presentation for TowerGame: the HUD is always mounted (it's the game's
-- only screen), so it registers as a root element rather than a UIShell window.
-- Discovered + required by init.client.luau before the root mounts; registration
-- is the only side effect.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local UIRegistry = require(ReplicatedStorage.Shared.Boil).UIRegistry
local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)

-- Client-realm sibling (StarterPlayerScripts.Features.TowerGame.TowerView).
local TowerView = require(script.Parent.TowerView)

if Constants.Presentations.hud then
	UIRegistry.registerRoot("TowerGame", React.createElement(TowerView))
end

return {}
