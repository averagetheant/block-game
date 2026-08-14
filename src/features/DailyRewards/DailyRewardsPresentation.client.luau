-- Screen presentation for DailyRewards: puts the window and its topbar button
-- into the root client tree. Discovered + required by init.client.luau before
-- the root mounts; registration is the only side effect (no Start lifecycle).
--
-- This is the one place that wires DailyRewards into the shell — the root
-- client file never names DailyRewards.
--
-- Both go in as *roots* rather than as a screen: a screen is content the
-- Sidebar rail mounts inside a window it renders for a rail entry, and this
-- feature has no rail entry. See docs/game/presentations.md.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local UIRegistry = require(ReplicatedStorage.Shared.Boil).UIRegistry
local Constants = require(ReplicatedStorage.Features.DailyRewards.Constants)

-- Client-realm siblings.
local DailyRewardsTopbar = require(script.Parent.DailyRewardsTopbar)
local DailyRewardsWindow = require(script.Parent.DailyRewardsWindow)

if Constants.Presentations.window then
	UIRegistry.registerRoot("DailyRewardsWindow", React.createElement(DailyRewardsWindow))
end

if Constants.Presentations.topbar then
	UIRegistry.registerRoot("DailyRewardsTopbar", React.createElement(DailyRewardsTopbar))
end

return {}
