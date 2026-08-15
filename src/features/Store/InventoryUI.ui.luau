--!strict
-- The inventory window's body: what the player owns, and what's equipped.
--
-- One tab per registered pack kind that wants the generic treatment ("pick one
-- pack, or none"), plus any tab a feature registered for itself — Reactions
-- ships its own, because assigning reactions to bar slots isn't "equip a pack".
--
-- InventoryView wires it to live data; InventoryUI.story drives ownership from
-- a UI Labs control against the real, discovered catalog.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ui = require(ReplicatedStorage.Shared.Boil).ui
local Catalog = require(script.Parent.Catalog)
local Constants = require(script.Parent.Constants)
local PackCard = require(script.Parent.PackCard)
local TabStrip = require(script.Parent.TabStrip)

export type Props = {
	-- packId → true.
	owned: { [string]: boolean },
	-- pack kind → equipped packId (absent = nothing equipped).
	equipped: { [string]: string },
	onEquip: (kind: string, packId: string) -> (),
	onUnequip: (kind: string) -> (),
	initialTab: string?,
	-- Called with the tab id whenever the player switches tabs. Optional, for
	-- the same reason as ShopUI's: the story renders with nothing behind it.
	onTabViewed: ((tabId: string) -> ())?,
}

local ROW_GAP = Constants.CARD_GAP
local EMPTY_TEXT_SIZE = ui.theme.textSizeRegular
local ACTION_HEIGHT = 48
local ACTION_TEXT_SIZE = ui.theme.textSizeRegular

local function root(children: { [string]: any }): any
	return React.createElement(ui.Stack, {
		gap = ROW_GAP,
		fillHorizontal = true,
		size = UDim2.new(1, 0, 0, 0),
		automaticSize = Enum.AutomaticSize.Y,
	}, children)
end

local function rowsFor(count: number): number
	return math.max(math.ceil(count / Constants.CARDS_PER_ROW), 1)
end

-- The generic "one equipped pack per kind" tab. The first card is always
-- "None": unequipping has to be as reachable as equipping, or a bought skin is
-- a one-way door.
--
-- None is a *choice in the grid*, not an escape hatch bolted onto it — so its
-- button reads "Equip" like every other card's, and shows the same green
-- "Equipped" badge when it's the one in use. It said "Unequip" before, which
-- described the code's intent (`onUnequip`) rather than the player's: in a row
-- of cards where you pick one, the odd verb out reads as a different kind of
-- control. The action it fires is still unequip.
local function packTab(kind: string, props: Props): { [string]: any }
	local ownedPacks = {}
	for _, pack in Catalog.listPacks(kind) do
		if props.owned[pack.id] == true then
			table.insert(ownedPacks, pack)
		end
	end

	local equippedId = props.equipped[kind]

	local cards: { [string]: any } = {
		None = React.createElement(PackCard, {
			name = "None",
			description = "No pack equipped — the game's own look.",
			layoutOrder = 0,
			dimmed = equippedId ~= nil,
			action = if equippedId == nil
				then React.createElement(ui.Badge, {
					variant = "green",
					text = "Equipped",
					textSize = ACTION_TEXT_SIZE,
					size = UDim2.new(1, 0, 0, ACTION_HEIGHT),
				})
				else React.createElement(ui.Button, {
					variant = "white",
					text = "Equip",
					textSize = ACTION_TEXT_SIZE,
					size = UDim2.new(1, 0, 0, ACTION_HEIGHT),
					onClick = function()
						props.onUnequip(kind)
					end,
				}),
		}),
	}

	for index, pack in ownedPacks do
		local isEquipped = equippedId == pack.id
		cards[`Pack_{pack.id}`] = React.createElement(PackCard, {
			name = pack.name,
			description = pack.description,
			icon = pack.icon,
			preview = Catalog.previewFor(pack),
			layoutOrder = index,
			action = if isEquipped
				then React.createElement(ui.Badge, {
					variant = "green",
					text = "Equipped",
					textSize = ACTION_TEXT_SIZE,
					size = UDim2.new(1, 0, 0, ACTION_HEIGHT),
				})
				else React.createElement(ui.Button, {
					variant = (pack.variant or "blue") :: any,
					text = "Equip",
					textSize = ACTION_TEXT_SIZE,
					size = UDim2.new(1, 0, 0, ACTION_HEIGHT),
					onClick = function()
						props.onEquip(kind, pack.id)
					end,
				}),
		})
	end

	-- +1 for the "None" card, which is always present.
	local rows = rowsFor(#ownedPacks + 1)
	local height = rows * Constants.CARD_HEIGHT + (rows - 1) * Constants.CARD_GAP

	return {
		Grid = React.createElement(ui.Grid, {
			cellSize = UDim2.fromOffset(Constants.CARD_WIDTH, Constants.CARD_HEIGHT),
			cellPadding = UDim2.fromOffset(Constants.CARD_GAP, Constants.CARD_GAP),
			horizontalAlignment = Enum.HorizontalAlignment.Center,
			size = UDim2.new(1, 0, 0, height),
			layoutOrder = 2,
		}, cards),
	}
end

return function(props: Props)
	local tabs: { TabStrip.Tab } = {}
	-- kind tabs first, then whatever features registered for themselves.
	for _, kind in Catalog.listKinds() do
		if kind.inventory ~= false then
			table.insert(tabs, { id = kind.id, title = kind.title })
		end
	end
	local registered = Catalog.listInventoryTabs()
	for _, tab in registered do
		table.insert(tabs, { id = tab.id, title = tab.title })
	end

	local activeTab, setActiveTab = React.useState(props.initialTab or (if tabs[1] then tabs[1].id else ""))

	-- Declared above the empty-state return below: hooks have to run in the same
	-- order on every render, and an early return between two of them is the one
	-- way to break that.
	local onSelect = React.useCallback(function(id: string)
		setActiveTab(id)
		if props.onTabViewed then
			props.onTabViewed(id)
		end
	end, { props.onTabViewed } :: { any })

	if #tabs == 0 then
		return root({
			Empty = React.createElement(ui.Text, {
				text = "Nothing to show yet — no packs are registered.",
				textSize = EMPTY_TEXT_SIZE,
				color = Color3.fromRGB(184, 192, 214),
				size = UDim2.new(1, 0, 0, 80),
				layoutOrder = 1,
			}),
		})
	end

	local tabExists = false
	for _, tab in tabs do
		if tab.id == activeTab then
			tabExists = true
			break
		end
	end
	local openTab = if tabExists then activeTab else tabs[1].id

	local children: { [string]: any } = {
		Tabs = React.createElement(TabStrip, {
			tabs = tabs,
			activeId = openTab,
			onSelect = onSelect,
			layoutOrder = 1,
		}),
	}

	-- A registered tab renders its own element and nothing else; the feature
	-- that registered it owns everything below the strip.
	for _, tab in registered do
		if tab.id ~= openTab then
			continue
		end
		children.Custom = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			LayoutOrder = 2,
		}, { Content = tab.element })
		return root(children)
	end

	for key, child in packTab(openTab, props) do
		children[key] = child
	end
	return root(children)
end
