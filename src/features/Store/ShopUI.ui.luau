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
	-- gamepassId → true. Separate from `owned` because a gamepass isn't a pack:
	-- it isn't bought with a currency, isn't equipped, and Roblox owns the
	-- answer rather than the profile.
	ownedGamepasses: { [number]: boolean },
	-- currencyId → balance. Not displayed — it's what decides whether a pack's
	-- buy button is affordable.
	balances: { [string]: number },
	onBuyPack: (packId: string) -> (),
	onBuyProduct: (productId: number) -> (),
	onBuyGamepass: (gamepassId: number) -> (),
	-- Story hook: forces the open tab instead of letting the strip own it.
	initialTab: string?,
	-- Called with the tab id whenever the player switches tabs. Optional: the
	-- UI Labs story renders this component with no wiring behind it, and a shop
	-- that only works when something is listening would be the wrong shape.
	onTabViewed: ((tabId: string) -> ())?,
}

local ROW_GAP = Constants.CARD_GAP
local SECTION_TEXT_SIZE = ui.theme.textSizeLarge
local SECTION_HEIGHT = SECTION_TEXT_SIZE + 10
local EMPTY_TEXT_SIZE = ui.theme.textSizeRegular
local ACTION_HEIGHT = 48
local ACTION_TEXT_SIZE = ui.theme.textSizeRegular

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

	-- Selecting a tab is both a state change and something worth reporting, and
	-- the two are kept apart: this owns the state, and `onTabViewed` is an
	-- optional callback the wiring layer fills in. The story renders without one.
	local onSelect = React.useCallback(function(id: string)
		setActiveTab(id)
		if props.onTabViewed then
			props.onTabViewed(id)
		end
	end, { props.onTabViewed } :: { any })

	local children: { [string]: any } = {
		Tabs = React.createElement(TabStrip, {
			tabs = tabs,
			activeId = openTab,
			onSelect = onSelect,
			layoutOrder = 1,
		}),
	}

	if openTab ~= ROBUX_TAB then
		-- Not `listPacks`: a reward-only pack (the daily run's grand prize) is a
		-- registered, ownable pack that simply has no card here. It shows up in
		-- the Inventory once it's been earned.
		local packs = Catalog.listForSale(openTab)
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
		-- A pass is owned forever, so the card that sold it becomes the card that
		-- confirms it — same treatment a bought pack gets.
		local owned = props.ownedGamepasses[pass.id] == true

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
				variant = (pass.variant or "purple") :: any,
				text = "Buy",
				textSize = ACTION_TEXT_SIZE,
				size = UDim2.new(1, 0, 0, ACTION_HEIGHT),
				onClick = function()
					props.onBuyGamepass(pass.id)
				end,
			})
		end

		passCards[`Pass_{pass.id}_{index}`] = React.createElement(PackCard, {
			name = pass.name,
			description = pass.description,
			icon = pass.icon,
			action = action,
			dimmed = owned,
			layoutOrder = index,
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
