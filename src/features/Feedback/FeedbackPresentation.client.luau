-- Screen presentation for Feedback: puts the topbar button into the root client
-- tree. Discovered + required by init.client.luau before the root mounts;
-- registration is the only side effect (no Start lifecycle).
--
-- A *root* rather than a screen, like the other two topbar buttons: a screen is
-- content the Sidebar rail mounts inside a window it renders, and this feature
-- has no window of its own to put anywhere — the panel it opens is Roblox's.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local UIRegistry = require(ReplicatedStorage.Shared.Boil).UIRegistry
local Constants = require(ReplicatedStorage.Features.Feedback.Constants)

-- Client-realm sibling.
local FeedbackTopbar = require(script.Parent.FeedbackTopbar)

if Constants.Presentations.topbar then
	UIRegistry.registerRoot("FeedbackTopbar", React.createElement(FeedbackTopbar))
end

return {}
