--!strict
-- A reaction pack's card art: the reactions it contains, drawn as themselves.
--
-- An icon can't say what's in a pack — four emoji packs would all be the same
-- picture with different names. Showing the contents is the honest preview, and
-- it's the same argument the skin packs make with their block viewport.
--
-- Every glyph goes through `ReactionGlyph`, which is the one place that knows a
-- reaction is either a TextLabel or an ImageLabel. So a pack of four emoji, a
-- pack of four images, and a pack that mixes them all render here without this
-- file learning the difference — which is exactly what the Brainrot pack (all
-- images) and the Emoji pack (three glyphs, one image) exist to prove.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ui = require(ReplicatedStorage.Shared.Boil).ui
local Catalog = require(script.Parent.Catalog)
local Constants = require(script.Parent.Constants)
local ReactionGlyph = require(script.Parent.ReactionGlyph)

export type Props = {
	packId: string,
}

-- The card's art slot is wide and short (roughly 204×88), so the contents read
-- best as one row rather than a square. A pack with more than this wraps onto a
-- second row on its own — nothing here assumes the count.
local PER_ROW = 4
local CELL_PADDING = 6

return function(props: Props)
	local reactions = Catalog.inPack(props.packId)
	if #reactions == 0 then
		return nil
	end

	local children: { [string]: any } = {}
	for index, reaction in reactions do
		-- Direct children of the grid, with no Size of their own: UIGridLayout
		-- reasserts CellSize every pass, so a wrapper that set its own would just
		-- be overwritten (see ui.Grid's note).
		children[`Cell_{reaction.id}`] = React.createElement(ReactionGlyph, {
			reactionId = reaction.id,
			-- Sized against the *cell* and through GLYPH_FIT, so an emoji's
			-- ascenders aren't shaved off — see that constant.
			textSize = math.floor(Constants.PREVIEW_CELL * Constants.GLYPH_FIT),
			layoutOrder = index,
			-- The grid owns position; the glyph fills the cell it's given.
			size = UDim2.fromScale(1, 1),
			position = UDim2.fromScale(0.5, 0.5),
			anchorPoint = Vector2.new(0.5, 0.5),
		})
	end

	return React.createElement(ui.Grid, {
		size = UDim2.fromScale(1, 1),
		cellSize = UDim2.fromOffset(Constants.PREVIEW_CELL, Constants.PREVIEW_CELL),
		cellPadding = UDim2.fromOffset(CELL_PADDING, CELL_PADDING),
		fillDirectionMaxCells = PER_ROW,
		horizontalAlignment = Enum.HorizontalAlignment.Center,
		verticalAlignment = Enum.VerticalAlignment.Center,
	}, children)
end
