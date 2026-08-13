-- Root presentation for Reactions: the bar and the float layer are always
-- mounted (the bar hides itself; it isn't a window), so this registers a root
-- element. Discovered + required by init.client.luau before the root mounts;
-- registration is the only side effect.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local UIRegistry = require(ReplicatedStorage.Shared.Boil).UIRegistry
local Constants = require(ReplicatedStorage.Features.Reactions.Constants)
local StoreCatalog = require(ReplicatedStorage.Features.Store.Catalog)
local PackPreview = require(ReplicatedStorage.Features.Reactions.PackPreview)

-- Client-realm sibling (StarterPlayerScripts.Features.Reactions.ReactionsView).
local ReactionsView = require(script.Parent.ReactionsView)

if Constants.Presentations.bar then
	UIRegistry.registerRoot("Reactions", React.createElement(ReactionsView))
end

-- Draw a reaction pack's shop card as the reactions inside it. Registered from
-- the client realm because the renderer returns a React element, so it can't
-- live in the shared Store.luau that registers the packs themselves.
StoreCatalog.registerPackPreview("reaction", function(pack)
	return React.createElement(PackPreview, { packId = pack.id })
end)

return {}
