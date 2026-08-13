--!strict
-- One reaction, drawn. The single place that knows a reaction is either a text
-- glyph or an image — the bar, the inventory grid and the float layer all go
-- through here, so adding a third kind is one edit rather than three.
--
-- Deliberately a raw TextLabel: emoji have to render in the system font, and
-- the gem display font (`ui.Text`) doesn't carry them — a `ui.Text` emoji comes
-- out as tofu.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Catalog = require(script.Parent.Catalog)
local Constants = require(script.Parent.Constants)

type Props = {
	reactionId: string,
	-- Text glyph size. Size this against the container by `Constants.GLYPH_FIT`
	-- rather than to the container itself — an emoji drawn at its box's full
	-- height loses its top and bottom to any parent that clips. Images scale to
	-- GLYPH_IMAGE_SCALE of the container instead and don't have the problem.
	textSize: number?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
	transparency: number?,
}

return function(props: Props)
	local reaction = Catalog.get(props.reactionId)
	if reaction == nil then
		return nil
	end

	local transparency = props.transparency or 0

	if reaction.kind == "image" then
		return React.createElement("ImageLabel", {
			Size = props.size or UDim2.fromScale(Constants.GLYPH_IMAGE_SCALE, Constants.GLYPH_IMAGE_SCALE),
			Position = props.position or UDim2.fromScale(0.5, 0.5),
			AnchorPoint = props.anchorPoint or Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = reaction.image or "",
			ImageTransparency = transparency,
			ScaleType = Enum.ScaleType.Fit,
			LayoutOrder = props.layoutOrder,
			ZIndex = props.zIndex,
		})
	end

	return React.createElement("TextLabel", {
		Size = props.size or UDim2.fromScale(1, 1),
		Position = props.position or UDim2.fromScale(0.5, 0.5),
		AnchorPoint = props.anchorPoint or Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = reaction.text or "",
		TextSize = props.textSize or Constants.GLYPH_TEXT_SIZE,
		TextTransparency = transparency,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		LayoutOrder = props.layoutOrder,
		ZIndex = props.zIndex,
	})
end
