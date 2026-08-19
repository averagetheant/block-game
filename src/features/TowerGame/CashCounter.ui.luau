--!strict
-- The money readout: the counter pinned in the bottom-right corner, and the
-- burst of bills that lands on it.
--
-- One component rather than a block in each HUD. Both modes pay out and both put
-- the total in the same corner — the size, the corner and the point the bills fly
-- at are one fact, and a fact written down twice drifts the moment one copy is
-- tuned. The classic HUD had it and PVP simply didn't, which is exactly the shape
-- that mistake takes.
--
-- Sizes live in `Constants` rather than here because the HUDs need them too: both
-- stack their camera toggle directly above this, and the classic progress rail
-- ends above the pair.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ui = require(ReplicatedStorage.Shared.Boil).ui

local CashFly = require(script.Parent.CashFly)
local Constants = require(script.Parent.Constants)

local WIDTH = Constants.CASH_WIDTH
local HEIGHT = Constants.CASH_HEIGHT
local EDGE_MARGIN = Constants.EDGE_MARGIN
local TEXT_SIZE = 32
local ICON = 34
-- The gap the number is given after the icon and the row's own gap are taken out.
local TEXT_INSET = 34

export type Props = {
	cash: number,
	-- Signal firing with an amount whenever cash arrives; drives the bill burst.
	-- Optional so a surface that only wants the number can leave the flourish off.
	awarded: any?,
}

return function(props: Props)
	local children: { [string]: any } = {
		Counter = React.createElement(ui.Panel, {
			size = UDim2.fromOffset(WIDTH, HEIGHT),
			position = UDim2.new(1, -EDGE_MARGIN, 1, -EDGE_MARGIN),
			anchorPoint = Vector2.new(1, 1),
		}, {
			Row = React.createElement(ui.Row, { gap = 8, size = UDim2.fromScale(1, 1) }, {
				Icon = React.createElement("ImageLabel", {
					Image = Constants.CASH_IMAGE,
					BackgroundTransparency = 1,
					Size = UDim2.fromOffset(ICON, ICON),
					LayoutOrder = 1,
				}),
				Amount = React.createElement(ui.Text, {
					text = tostring(props.cash),
					textSize = TEXT_SIZE,
					weight = Enum.FontWeight.Heavy,
					shadow = true,
					xAlignment = Enum.TextXAlignment.Left,
					size = UDim2.fromOffset(WIDTH - ICON - TEXT_INSET, HEIGHT),
					layoutOrder = 2,
				}),
			}),
		}),
	}

	if props.awarded then
		children.Fly = React.createElement(CashFly, {
			awarded = props.awarded,
			-- Kept in step with the counter's own anchor above.
			target = UDim2.new(1, -(EDGE_MARGIN + WIDTH / 2), 1, -(EDGE_MARGIN + HEIGHT / 2)),
		})
	end

	-- A transparent slot over the whole screen, because the two halves live in
	-- different places: the counter is pinned to a corner and the bills start in
	-- the middle of the display. Nothing here is drawn.
	return React.createElement(ui.Slot, {
		name = "CashCounter",
		size = UDim2.fromScale(1, 1),
	}, children)
end
