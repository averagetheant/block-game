-- Root presentation for VoiceChat: the speaker column is always mounted (it
-- draws nothing when nobody is talking, so it isn't a window), so this registers
-- a root element rather than a screen.
--
-- Discovered + required by init.client.luau before the root mounts; registration
-- is the only side effect. Turning `Presentations.screen` off drops the chips
-- and leaves the voice routing untouched — VoiceController does that work, and
-- it isn't a presentation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local UIRegistry = require(ReplicatedStorage.Shared.Boil).UIRegistry
local Constants = require(ReplicatedStorage.Features.VoiceChat.Constants)

-- Client-realm sibling (StarterPlayerScripts.Features.VoiceChat.VoiceView).
local VoiceView = require(script.Parent.VoiceView)

if Constants.Presentations.screen then
	UIRegistry.registerRoot("VoiceChat", React.createElement(VoiceView))
end

return {}
