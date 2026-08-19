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

		-- A pack that pins a BlockSkin (Needoh) is drawn as that skin: its
		-- material, its transparency and the display colour the skin carries for
		-- exactly this — being rendered outside the game, where there's no roll.
		local pinned = SkinPacks.blockSkinFor(skin)

		-- One fixed shade per card rather than a fresh roll: in game every block
		-- rolls its own, but a tile that re-coloured itself on each re-render
		-- would look broken. `colorFor` returns nil for a pack that isn't about
		-- hue (Neon), which then shows in white so the *material* is what reads.
		local color = SkinPacks.colorFor(skin)
			or (if pinned then pinned.color else nil)
			or Color3.fromRGB(236, 240, 252)

		return React.createElement(BlockPreview, {
			color = color,
			material = skin.material or (if pinned then pinned.material else nil),
			transparency = if pinned then pinned.transparency else nil,
			-- Only a pinned skin can carry one — a texture is part of what a
			-- BlockSkin *is*, and no pack sets one of its own.
			texture = if pinned then pinned.texture else nil,
		})
	end)
end

return {}
