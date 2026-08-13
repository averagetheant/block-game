-- Screen presentation for GamemodeVote.
--
-- Registered as a *root* rather than a HUD window slot: nothing in the sidebar
-- opens a vote, the server does — so the container is always mounted and renders
-- nothing until a poll arrives, at which point it opens its own UIShell frame.
--
-- Discovered + required by init.client.luau before the root mounts; registration
-- is the only side effect.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local UIRegistry = require(ReplicatedStorage.Shared.Boil).UIRegistry
local Constants = require(ReplicatedStorage.Features.GamemodeVote.Constants)

-- Client-realm sibling (StarterPlayerScripts.Features.GamemodeVote.GamemodeVoteView).
local GamemodeVoteView = require(script.Parent.GamemodeVoteView)

if Constants.Presentations.screen then
	UIRegistry.registerRoot("GamemodeVote", React.createElement(GamemodeVoteView))
end

return {}
