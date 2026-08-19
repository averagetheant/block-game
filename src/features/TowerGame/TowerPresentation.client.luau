-- Root presentation for TowerGame: the HUD is always mounted (it's the game's
-- only screen), so it registers as a root element rather than a UIShell window.
-- Discovered + required by init.client.luau before the root mounts; registration
-- is the only side effect.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local UIRegistry = require(ReplicatedStorage.Shared.Boil).UIRegistry
local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)

-- Client-realm siblings (StarterPlayerScripts.Features.TowerGame.*).
local TowerCashView = require(script.Parent.TowerCashView)
local TowerView = require(script.Parent.TowerView)

if Constants.Presentations.hud then
	UIRegistry.registerRoot("TowerGame", React.createElement(TowerView))
	-- The money readout is its own root, on its own layer: both modes pay out,
	-- and the bills have to land in front of whatever window the player claimed
	-- something in. See TowerCashView.
	UIRegistry.registerRoot("TowerGameCash", React.createElement(TowerCashView))
end

return {}
