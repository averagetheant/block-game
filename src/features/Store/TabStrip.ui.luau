--!strict
-- A row of tab buttons. Purely an arrangement of `ui.Button` — no new look, so
-- it lives here rather than in the skin contract: the active tab is just a
-- brighter variant, which every skin already draws.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ui = require(ReplicatedStorage.Shared.Boil).ui
local Constants = require(script.Parent.Constants)

export type Tab = {
	id: string,
	title: string,
}

type Props = {
	tabs: { Tab },
	activeId: string,
	onSelect: (id: string) -> (),
	layoutOrder: number?,
}

-- The active tab is the one gem in the row; the rest read as its background.
local ACTIVE_VARIANT = "yellow"
local IDLE_VARIANT = "white"

return function(props: Props)
	local children: { [string]: any } = {}

	for index, tab in props.tabs do
		local active = tab.id == props.activeId
		children[`Tab_{tab.id}`] = React.createElement(ui.Button, {
			variant = (if active then ACTIVE_VARIANT else IDLE_VARIANT) :: any,
			text = tab.title,
			textSize = Constants.TAB_TEXT_SIZE,
			-- Flex spreads these to fill the strip; the offset is just a floor.
			size = UDim2.new(0, 120, 1, 0),
			layoutOrder = index,
			onClick = function()
				props.onSelect(tab.id)
			end,
		})
	end

	return React.createElement(ui.Row, {
		gap = Constants.TAB_GAP,
		fillHorizontal = true,
		size = UDim2.new(1, 0, 0, Constants.TAB_HEIGHT),
		layoutOrder = props.layoutOrder,
	}, children)
end
