-- Root presentations for the two spectator surfaces: the inactivity card and the
-- "Not playing" badge. Both always mounted, each drawing only when the controller
-- says so.
--
-- Discovered + required by init.client.luau before the root mounts; registration
-- is the only side effect. Turning `Presentations.afk` off drops the card and
-- leaves the benching itself alone — that's TowerService's rule, not a surface.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local UIRegistry = require(ReplicatedStorage.Shared.Boil).UIRegistry
local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)

-- Client-realm siblings (StarterPlayerScripts.Features.TowerGame.*).
local TowerAfkView = require(script.Parent.TowerAfkView)
local TowerSpectatorView = require(script.Parent.TowerSpectatorView)

-- Two roots, because they stack differently and a root's own ZIndex is the only
-- thing that can say so: the card draws over everything, the badge draws under
-- the HUD. One gate, because they're one feature — turning `afk` off takes both
-- surfaces and leaves the benching itself alone.
if Constants.Presentations.afk then
	UIRegistry.registerRoot("TowerAfk", React.createElement(TowerAfkView))
	UIRegistry.registerRoot("TowerSpectator", React.createElement(TowerSpectatorView))
end

return {}
