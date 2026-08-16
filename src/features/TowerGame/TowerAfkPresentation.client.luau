-- Root presentation for the inactivity card: always mounted, draws only when the
-- controller says the player has been dropped from the rotation.
--
-- Discovered + required by init.client.luau before the root mounts; registration
-- is the only side effect. Turning `Presentations.afk` off drops the card and
-- leaves the benching itself alone — that's TowerService's rule, not a surface.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local UIRegistry = require(ReplicatedStorage.Shared.Boil).UIRegistry
local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)

-- Client-realm sibling (StarterPlayerScripts.Features.TowerGame.TowerAfkView).
local TowerAfkView = require(script.Parent.TowerAfkView)

if Constants.Presentations.afk then
	UIRegistry.registerRoot("TowerAfk", React.createElement(TowerAfkView))
end

return {}
