--!strict
-- The shop window's body: a tab per registered pack kind, plus a Robux tab.
--
-- Content comes from the Catalog (shared, presentation-agnostic data — the same
-- relationship SettingsUI has with the Settings registry). What the *player*
-- has comes in as props, because that's replica state and a view doesn't fetch.
--
-- ShopView wires it to live data; ShopUI.story drives ownership and balances
-- from UI Labs controls against the real, discovered catalog.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ui = require(ReplicatedStorage.Shared.Boil).ui
local Catalog = require(script.Parent.Catalog)
local Constants = require(script.Parent.Constants)
local PackCard = require(script.Parent.PackCard)
local TabStrip = require(script.Parent.TabStrip)

-- The Robux tab isn't a pack kind — nothing is registered under it — so it gets
-- a reserved tab id. The id becomes a React key and therefore an instance name,
-- so it has to stay a legal one (a NUL sentinel gets silently stripped and the
-- tab shows up in the tree as "Tab_").
local ROBUX_TAB = "__robux"

export type Props = {
	-- packId → true.
	owned: { [string]: boolean },
	-- currencyId → balance.
	balances: { [string]: number },
	onBuyPack: (packId: string) -> (),
	onBuyProduct: (productId: number) -> (),
	onBuyGamepass: (gamepassId: number) -> (),
	-- Story hook: forces the open tab instead of letting the strip own it.
	initialTab: string?,
}

local ROW_GAP = Constants.CARD_GAP
local SECTION_TEXT_SIZE = 30
local SECTION_HEIGHT = 40
local EMPTY_TEXT_SIZE = 24
local ACTION_HEIGHT = 48
local ACTION_TEXT_SIZE = 24

local function grid(children: { [string]: any }, rows: number, layoutOrder: number): any
	return React.createElement(ui.Grid, {
		cellSize = UDim2.fromOffset(Constants.CARD_WIDTH, Constants.CARD_HEIGHT),
		cellPadding = UDim2.fromOffset(Constants.CARD_GAP, Constants.CARD_GAP),
		horizontalAlignment = Enum.HorizontalAlignment.Center,
		size = UDim2.new(1, 0, 0, rows * Constants.CARD_HEIGHT + math.max(rows - 1, 0) * Constants.CARD_GAP),
		layoutOrder = layoutOrder,
	}, children)
end

-- How many rows a grid of `count` cards needs. The window is a fixed size and
-- the cards are a fixed size, so this is arithmetic rather than measurement —
-- the grid still centers itself, this only sets the height it needs.
local function rowsFor(count: number): number
	return math.max(math.ceil(count / Constants.CARDS_PER_ROW), 1)
end

local function sectionHeader(text: string, layoutOrder: number): any
	return React.createElement(ui.Text, {
		text = text,
		textSize = SECTION_TEXT_SIZE,
		weight = Enum.FontWeight.Heavy,
		shadow = true,
		xAlignment = Enum.TextXAlignment.Left,
		size = UDim2.new(1, 0, 0, SECTION_HEIGHT),
		layoutOrder = layoutOrder,
	})
end

-- The window body is a fixed-width scroll area, so the tab's content just has
-- to grow downward; height follows the grids.
local function root(children: { [string]: any }): any
	return React.createElement(ui.Stack, {
		gap = ROW_GAP,
		fillHorizontal = true,
		size = UDim2.new(1, 0, 0, 0),
		automaticSize = Enum.AutomaticSize.Y,
	}, children)
end

-- What the player has to spend, one pill per registered currency, pushed to the
-- right so it reads as a status line rather than a heading. It sits above the
-- tabs because it's true of every tab.
local function balanceRow(balances: { [string]: number }, layoutOrder: number): any?
	local currencies = Catalog.listCurrencies()
	if #currencies == 0 then
		return nil
	end

	local pills: { [string]: any } = {}
	for index, currency in currencies do
		pills[`Balance_{currency.id}`] = React.createElement(ui.Badge, {
			variant = "blue",
			icon = currency.icon,
			text = tostring(balances[currency.id] or 0),
			textSize = Constants.TAB_TEXT_SIZE,
			size = UDim2.fromOffset(Constants.BALANCE_WIDTH, Constants.BALANCE_HEIGHT),
			layoutOrder = index,
		})
	end

	return React.createElement(ui.Row, {
		gap = Constants.TAB_GAP,
		horizontalAlignment = Enum.HorizontalAlignment.Right,
		size = UDim2.new(1, 0, 0, Constants.BALANCE_HEIGHT),
		layoutOrder = layoutOrder,
	}, pills)
end

local function emptyState(text: string, layoutOrder: number): any
	return React.createElement(ui.Text, {
		text = text,
		textSize = EMPTY_TEXT_SIZE,
		color = Color3.fromRGB(184, 192, 214),
		size = UDim2.new(1, 0, 0, 80),
		layoutOrder = layoutOrder,
	})
end

return function(props: Props)
	local kinds = Catalog.listKinds()

	local tabs: { TabStrip.Tab } = {}
	for _, kind in kinds do
		table.insert(tabs, { id = kind.id, title = kind.title })
	end
	table.insert(tabs, { id = ROBUX_TAB, title = "Robux" })

	local defaultTab = props.initialTab or tabs[1].id
	local activeTab, setActiveTab = React.useState(defaultTab)

	-- A tab can disappear under the player (a feature uninstalled between
	-- sessions, a story swapping catalogs). Fall back rather than render blank.
	local tabExists = false
	for _, tab in tabs do
		if tab.id == activeTab then
			tabExists = true
			break
		end
	end
	local openTab = if tabExists then activeTab else tabs[1].id

	local children: { [string]: any } = {
		Balances = balanceRow(props.balances, 0),
		Tabs = React.createElement(TabStrip, {
			tabs = tabs,
			activeId = openTab,
			onSelect = setActiveTab,
			layoutOrder = 1,
		}),
	}

	if openTab ~= ROBUX_TAB then
		local packs = Catalog.listPacks(openTab)
		local cards: { [string]: any } = {}

		for index, pack in packs do
			local owned = props.owned[pack.id] == true
			local currency = Catalog.getCurrency(pack.currency)
			local affordable = (props.balances[pack.currency] or 0) >= pack.price

			local action
			if owned then
				action = React.createElement(ui.Badge, {
					variant = "green",
					text = "Owned",
					textSize = ACTION_TEXT_SIZE,
					size = UDim2.new(1, 0, 0, ACTION_HEIGHT),
				})
			else
				action = React.createElement(ui.Button, {
					variant = (pack.variant or "green") :: any,
					text = `{pack.price} {if currency then currency.name else pack.currency}`,
					textSize = ACTION_TEXT_SIZE,
					size = UDim2.new(1, 0, 0, ACTION_HEIGHT),
					-- Still shown, just inert: a price you can't meet yet is
					-- information, and hiding it hides the goal.
					disabled = not affordable,
					onClick = function()
						props.onBuyPack(pack.id)
					end,
				})
			end

			cards[`Pack_{pack.id}`] = React.createElement(PackCard, {
				name = pack.name,
				description = pack.description,
				icon = pack.icon,
				-- nil unless the owning feature registered a renderer for this
				-- kind, in which case it replaces the icon in the art slot.
				preview = Catalog.previewFor(pack),
				action = action,
				dimmed = owned,
				layoutOrder = index,
			})
		end

		if #packs == 0 then
			children.Empty = emptyState("Nothing for sale here yet.", 2)
		else
			children.Packs = grid(cards, rowsFor(#packs), 2)
		end

		return root(children)
	end

	-- Robux tab: currency bundles on top, gamepasses underneath.
	local products = Catalog.listProducts("currency")
	local productCards: { [string]: any } = {}
	for index, product in products do
		productCards[`Product_{product.id}`] = React.createElement(PackCard, {
			name = product.name,
			description = product.description,
			icon = product.icon,
			layoutOrder = index,
			action = React.createElement(ui.Button, {
				variant = (product.variant or "green") :: any,
				text = "Buy",
				textSize = ACTION_TEXT_SIZE,
				size = UDim2.new(1, 0, 0, ACTION_HEIGHT),
				onClick = function()
					props.onBuyProduct(product.id)
				end,
			}),
		})
	end

	children.CurrencyHeader = sectionHeader("Currency", 2)
	if #products == 0 then
		children.CurrencyEmpty = emptyState("No currency bundles registered.", 3)
	else
		children.Currency = grid(productCards, rowsFor(#products), 3)
	end

	local gamepasses = Catalog.listGamepasses()
	local passCards: { [string]: any } = {}
	for index, pass in gamepasses do
		passCards[`Pass_{pass.id}_{index}`] = React.createElement(PackCard, {
			name = pass.name,
			description = pass.description,
			icon = pass.icon,
			layoutOrder = index,
			action = React.createElement(ui.Button, {
				variant = (pass.variant or "purple") :: any,
				text = "Buy",
				textSize = ACTION_TEXT_SIZE,
				size = UDim2.new(1, 0, 0, ACTION_HEIGHT),
				onClick = function()
					props.onBuyGamepass(pass.id)
				end,
			}),
		})
	end

	children.PassHeader = sectionHeader("Gamepasses", 4)
	if #gamepasses == 0 then
		children.PassEmpty = emptyState("No gamepasses registered.", 5)
	else
		children.Passes = grid(passCards, rowsFor(#gamepasses), 5)
	end

	return root(children)
end
