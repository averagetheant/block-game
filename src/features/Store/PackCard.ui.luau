--!strict
-- One tile in a shop or inventory grid: art on top, name, a line of copy, and
-- whatever the caller wants along the bottom (a Buy button, an Equip button, an
-- "Owned" badge). The card knows nothing about prices or ownership — it draws
-- what it's handed, which is what lets the same tile serve both windows.
--
-- The art slot takes either an image (`icon`) or a caller-supplied element
-- (`preview`), because not every pack has a picture: a reaction pack's honest
-- preview is its emoji, which is a text label.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ui = require(ReplicatedStorage.Shared.Boil).ui
local Constants = require(script.Parent.Constants)

type Props = {
	name: string,
	description: string?,
	icon: string?,
	-- Overrides `icon`; mounted into the same square art slot.
	preview: any?,
	-- Bottom row. Usually a ui.Button or ui.Badge sized (1, 0, 0, ACTION_HEIGHT).
	action: any?,
	-- Dims the whole tile — for a pack the player can't act on yet.
	dimmed: boolean?,
	layoutOrder: number?,
}

local ACTION_HEIGHT = 48
-- Both labels sit on the shared ladder: the pack name and its description are
-- the copy a player reads to decide on a purchase, so neither drops below the
-- body floor. CARD_HEIGHT is sized to hold the description at this tier.
local NAME_TEXT_SIZE = ui.theme.textSizeRegular
local NAME_HEIGHT = NAME_TEXT_SIZE + 8
local DESC_TEXT_SIZE = ui.theme.textSizeRegular
local GAP = 6

local DESC_COLOR = Color3.fromRGB(196, 203, 224)

return function(props: Props)
	local theme = ui.useSkin().theme
	-- The panel is stroked, so content sits `padding + strokeThickness` in from
	-- the edge or it visually crowds the outline. Computed here so a live theme
	-- edit propagates (see CLAUDE.md § stroke thickness).
	local inset = theme.padding + theme.strokeThickness

	local art = props.preview
	if art == nil and props.icon ~= nil then
		art = React.createElement("ImageLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = props.icon,
			ScaleType = Enum.ScaleType.Fit,
			ImageTransparency = if props.dimmed then 0.5 else 0,
		})
	end

	local descriptionTop = Constants.CARD_ICON + GAP + NAME_HEIGHT + GAP

	return React.createElement(ui.Panel, {
		size = UDim2.fromOffset(Constants.CARD_WIDTH, Constants.CARD_HEIGHT),
		-- Panel centers itself by default. A grid cell owns its own Position but
		-- not its AnchorPoint, so leaving the default would slide every card half
		-- a tile up and left of where the layout put it.
		position = UDim2.fromScale(0, 0),
		anchorPoint = Vector2.new(0, 0),
		layoutOrder = props.layoutOrder,
	}, {
		UIPadding = React.createElement("UIPadding", {
			PaddingTop = UDim.new(0, inset),
			PaddingBottom = UDim.new(0, inset),
			PaddingLeft = UDim.new(0, inset),
			PaddingRight = UDim.new(0, inset),
		}),

		Art = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, Constants.CARD_ICON),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, if art ~= nil then { Content = art } else {}),

		Name = React.createElement(ui.Text, {
			text = props.name,
			textSize = NAME_TEXT_SIZE,
			weight = Enum.FontWeight.Heavy,
			shadow = true,
			size = UDim2.new(1, 0, 0, NAME_HEIGHT),
			position = UDim2.fromOffset(0, Constants.CARD_ICON + GAP),
		}),

		Description = if props.description ~= nil
			then React.createElement(ui.Text, {
				text = props.description,
				textSize = DESC_TEXT_SIZE,
				color = DESC_COLOR,
				wrapped = true,
				yAlignment = Enum.TextYAlignment.Top,
				size = UDim2.new(1, 0, 1, -(descriptionTop + ACTION_HEIGHT + GAP)),
				position = UDim2.fromOffset(0, descriptionTop),
			})
			else nil,

		Action = if props.action ~= nil
			then React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, ACTION_HEIGHT),
				Position = UDim2.new(0.5, 0, 1, 0),
				AnchorPoint = Vector2.new(0.5, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
			}, { Content = props.action })
			else nil,
	})
end
