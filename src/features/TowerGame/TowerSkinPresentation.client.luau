-- Draws the skin packs' shop and inventory cards as a real block instead of an
-- icon. Registered here rather than in TowerGame/Store.luau because the renderer
-- returns a React element, and a shared Store.luau loads on the server too.
--
-- This is the seam working as intended: Store owns the card and knows nothing
-- about blocks; TowerGame owns what a skin *is* and hands back something that
-- shows it. A card for any other kind is unaffected and keeps its icon.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Catalog = require(ReplicatedStorage.Features.Store.Catalog)
local BlockPreview = require(ReplicatedStorage.Features.TowerGame.BlockPreview)
local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)
local SkinPacks = require(ReplicatedStorage.Features.TowerGame.SkinPacks)

if Constants.Presentations.actions then
	Catalog.registerPackPreview(SkinPacks.KIND, function(pack)
		local skin = SkinPacks.get(pack.id)
		if skin == nil then
			return nil
		end

		-- One fixed shade per card rather than a fresh roll: in game every block
		-- rolls its own, but a tile that re-coloured itself on each re-render
		-- would look broken. `colorFor` returns nil for a material pack (Neon),
		-- which then shows in white so the *material* is what reads.
		return React.createElement(BlockPreview, {
			color = SkinPacks.colorFor(skin) or Color3.fromRGB(236, 240, 252),
			material = skin.material,
		})
	end)
end

return {}
