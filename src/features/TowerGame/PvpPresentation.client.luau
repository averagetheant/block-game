-- Root presentation for the PVP round.
--
-- Registered as its own root beside the classic HUD rather than as a branch
-- inside it: the two draw nothing in common, and a single component that tried to
-- be both would be a file where every line asks which mode it's in. Each renders
-- nil while the other owns the board, so exactly one is ever on screen.
--
-- Discovered + required by init.client.luau before the root mounts; registration
-- is the only side effect.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local UIRegistry = require(ReplicatedStorage.Shared.Boil).UIRegistry
local PvpConstants = require(ReplicatedStorage.Features.TowerGame.PvpConstants)

-- Client-realm sibling (StarterPlayerScripts.Features.TowerGame.PvpView).
local PvpView = require(script.Parent.PvpView)

if PvpConstants.Presentations.hud then
	UIRegistry.registerRoot("TowerGamePvp", React.createElement(PvpView))
end

return {}
