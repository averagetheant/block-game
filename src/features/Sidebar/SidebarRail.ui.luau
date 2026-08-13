--!strict
-- The left rail as it actually appears in game: every registered entry, plus a
-- UIShell frame + Window for the ones that open something.
--
-- It names no feature. The entries come from the Sidebar registry and the window
-- *contents* come from the screen registry, so a feature appears on the rail by
-- registering into both — this file never learns what Shop or Inventory are.
--
-- Two clusters stack in one column: "menu" (navigation — opens frames) above
-- "actions" (one-shot buttons) with a wider gap between them. The whole thing
-- rides inside HideWhenFrameOpen, so opening a window slides the rail out of the
-- way rather than leaving it sitting under the frame.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Features = ReplicatedStorage:WaitForChild("Features")

local React = require(ReplicatedStorage.Packages.React)
local Boil = require(ReplicatedStorage.Shared.Boil)
local ui = Boil.ui
local UIRegistry = Boil.UIRegistry
local UIShell = require(Features:WaitForChild("UIShell"))

local Constants = require(script.Parent.Constants)
local Registry = require(script.Parent.Registry)
local SidebarColumn = require(script.Parent.Sidebar)

type Props = {
	-- Overrides the screen registry, for the UI Labs story.
	frameContents: { [string]: any }?,
	-- Overrides the sidebar registry, for the UI Labs story.
	menu: { Registry.Entry }?,
	actions: { Registry.Entry }?,
}

local ITEM_SIZE = Constants.DEFAULT_ICON_SIZE
local PADDING = Constants.PADDING
local SPACING = Constants.ITEM_SPACING
local RAIL_WIDTH = ITEM_SIZE + PADDING * 2

-- Height of one cluster: its items plus the column's own top/bottom padding.
local function columnHeight(count: number): number
	if count == 0 then
		return 0
	end
	return count * ITEM_SIZE + (count - 1) * SPACING + PADDING * 2
end

-- Re-read the registry whenever something registers late (a presentation loaded
-- after the root mounted, a feature that registers on demand).
local function useRegistryVersion()
	local _, setVersion = React.useState(0)
	React.useEffect(function()
		local conn = Registry.Changed:Connect(function()
			setVersion(function(v: number): number
				return v + 1
			end)
		end)
		return function()
			conn:Disconnect()
		end
	end, {})
end

return function(props: Props)
	useRegistryVersion()

	local frames = UIShell.useFrame()
	local frameContents = props.frameContents or UIRegistry.getScreens()
	local menu = props.menu or Registry.list("menu")
	local actions = props.actions or Registry.list("actions")

	-- One item per entry. Clicking either toggles the entry's frame or runs its
	-- action — the rail doesn't care which, it just calls what the entry declared.
	local function itemsFor(entries: { Registry.Entry })
		local items = {}
		for _, entry in entries do
			local frameId = Registry.frameIdOf(entry)
			table.insert(items, {
				id = entry.id,
				icon = entry.icon,
				label = entry.label,
				onClick = function()
					if frameId ~= nil then
						frames.toggle(frameId)
						return
					end
					if entry.onClick then
						entry.onClick()
					end
				end,
			})
		end
		return items
	end

	local columns: { [string]: any } = {}
	if #menu > 0 then
		columns.Menu = React.createElement(SidebarColumn, {
			items = itemsFor(menu),
			size = UDim2.fromOffset(RAIL_WIDTH, columnHeight(#menu)),
			layoutOrder = 1,
		})
	end
	if #actions > 0 then
		columns.Actions = React.createElement(SidebarColumn, {
			items = itemsFor(actions),
			size = UDim2.fromOffset(RAIL_WIDTH, columnHeight(#actions)),
			layoutOrder = 2,
		})
	end

	local railHeight = columnHeight(#menu) + columnHeight(#actions)
	if #menu > 0 and #actions > 0 then
		railHeight += Constants.GROUP_GAP
	end

	-- The rail sits on the left edge, which on a phone in landscape is where the
	-- notch is — so the margin is measured from the usable edge, not the screen's.
	local insets = ui.useViewport().insets

	local children: { [string]: any } = {
		Rail = React.createElement(UIShell.HideWhenFrameOpen, {
			direction = "left",
			basePosition = UDim2.new(0, Constants.RAIL_MARGIN + insets.left, 0.5, 0),
			anchorPoint = Vector2.new(0, 0.5),
			size = UDim2.fromOffset(RAIL_WIDTH, railHeight),
		}, {
			Clusters = React.createElement(ui.Stack, {
				gap = Constants.GROUP_GAP,
				size = UDim2.fromScale(1, 1),
			}, columns),
		}),
	}

	-- One frame per entry that opens one. An entry with no registered content
	-- still opens — an empty window is a truer signal than a silent button that
	-- the feature forgot its `registerScreen`.
	for _, entry in menu do
		local frameId = Registry.frameIdOf(entry)
		if frameId == nil then
			continue
		end
		local content = frameContents[frameId]
		children[`{entry.id}Frame`] = React.createElement(UIShell.Frame, {
			id = frameId,
		}, {
			Window = React.createElement(ui.Window, {
				size = entry.windowSize or Constants.WINDOW_SIZE,
				title = entry.windowTitle or entry.label,
				icon = entry.icon,
				titleVariant = entry.titleVariant :: any,
				onClose = frames.close,
			}, if content ~= nil then { Content = content } else {}),
		})
	end

	return React.createElement("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, children)
end
