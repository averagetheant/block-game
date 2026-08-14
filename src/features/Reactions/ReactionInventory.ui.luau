--!strict
-- The Reactions tab inside the Inventory window.
--
-- Two halves: the bar as it currently is (pick the slot you want to change),
-- and every reaction that exists (pick what goes in it). Two clicks, and the
-- first one is remembered — assigning four reactions is four clicks after the
-- initial pick, not eight.
--
-- Unowned reactions are shown, dimmed. Hiding them would hide the reason to buy
-- the pack.
--
-- Dumb: slots, ownership and the assign callback all come in as props.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ui = require(ReplicatedStorage.Shared.Boil).ui
local Catalog = require(script.Parent.Catalog)
local Constants = require(script.Parent.Constants)
local ReactionGlyph = require(script.Parent.ReactionGlyph)

export type Props = {
	-- One reaction id per bar slot, in bar order.
	slots: { string },
	-- reactionId → true.
	owned: { [string]: boolean },
	onAssign: (index: number, reactionId: string) -> (),
}

local SLOT_SIZE = 84
local TILE_WIDTH = 124
local TILE_HEIGHT = 146
local TILE_GAP = 12
-- The glyph's *box*. Its text is sized against GLYPH_FIT rather than filling the
-- box, or an emoji's ascenders get shaved off at the top — see that constant.
local TILE_GLYPH = 62
local TILE_GLYPH_TEXT = math.floor(TILE_GLYPH * Constants.GLYPH_FIT)
-- The bar's own glyph size is tuned for the bar's much smaller button, so the
-- inventory's larger slots derive their own instead of borrowing it.
local SLOT_GLYPH_TEXT = math.floor(SLOT_SIZE * Constants.GLYPH_FIT)
-- Glyph sizes above derive from their boxes (GLYPH_FIT); the label sizes below
-- are ordinary copy and sit on the shared ladder instead. Each HEIGHT is the
-- tier plus breathing room, so re-tiering a label moves its row rather than
-- clipping it.
local NAME_TEXT_SIZE = ui.theme.textSizeRegular
local NAME_HEIGHT = NAME_TEXT_SIZE + 8
local HEADER_TEXT_SIZE = ui.theme.textSizeLarge
local HEADER_HEIGHT = HEADER_TEXT_SIZE + 10
local HINT_TEXT_SIZE = ui.theme.textSizeRegular
-- Two lines: the hint is a full sentence and wraps at the window's body width.
local HINT_HEIGHT = HINT_TEXT_SIZE * 2 + 8
local ROW_GAP = 12

local DIM_COLOR = Color3.fromRGB(184, 192, 214)
-- How many tiles fit per row at the inventory window's body width. Fixed rather
-- than measured — the window is a fixed size, so this can be arithmetic.
local TILES_PER_ROW = 5

local function header(text: string, layoutOrder: number): any
	return React.createElement(ui.Text, {
		text = text,
		textSize = HEADER_TEXT_SIZE,
		weight = Enum.FontWeight.Heavy,
		shadow = true,
		xAlignment = Enum.TextXAlignment.Left,
		size = UDim2.new(1, 0, 0, HEADER_HEIGHT),
		layoutOrder = layoutOrder,
	})
end

return function(props: Props)
	-- Which bar slot the next pick lands in. Slot 1 by default so the tab is
	-- usable without reading anything first.
	local selected, setSelected = React.useState(1)

	local slotChildren: { [string]: any } = {}
	for index, reactionId in props.slots do
		local isSelected = index == selected
		slotChildren[`Slot{index}`] = React.createElement(ui.Panel, {
			size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE),
			position = UDim2.fromScale(0, 0),
			anchorPoint = Vector2.new(0, 0),
			-- The selected slot lifts out of the row rather than gaining a
			-- badge — there's no room for one at this size.
			transparency = if isSelected then 0.35 else nil,
			layoutOrder = index,
		}, {
			Button = React.createElement("TextButton", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Text = "",
				[React.Event.Activated] = function()
					setSelected(index)
				end,
			}, {
				Glyph = React.createElement(ReactionGlyph, {
					reactionId = reactionId,
					textSize = SLOT_GLYPH_TEXT,
				}),
			}),
		})
	end

	local reactions = Catalog.list()
	local tiles: { [string]: any } = {}
	local anyLocked = false
	for index, reaction in reactions do
		local isOwned = props.owned[reaction.id] == true
		if not isOwned then
			anyLocked = true
		end
		tiles[`Reaction_{reaction.id}`] = React.createElement(ui.Panel, {
			size = UDim2.fromOffset(TILE_WIDTH, TILE_HEIGHT),
			position = UDim2.fromScale(0, 0),
			anchorPoint = Vector2.new(0, 0),
			layoutOrder = index,
		}, {
			Button = React.createElement("TextButton", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Text = "",
				Active = isOwned,
				[React.Event.Activated] = function()
					if not isOwned then
						return
					end
					props.onAssign(selected, reaction.id)
				end,
			}, {
				Glyph = React.createElement(ReactionGlyph, {
					reactionId = reaction.id,
					textSize = TILE_GLYPH_TEXT,
					size = UDim2.fromOffset(TILE_GLYPH, TILE_GLYPH),
					position = UDim2.new(0.5, 0, 0, 14),
					anchorPoint = Vector2.new(0.5, 0),
					transparency = if isOwned then 0 else 0.6,
				}),
				-- The name stays on a locked tile. Replacing it with "Locked"
				-- made all four unowned reactions read identically, which hides
				-- exactly the thing that would make someone want the pack; the
				-- dimmed glyph and the hint line below carry "locked" instead.
				Name = React.createElement(ui.Text, {
					text = reaction.name,
					textSize = NAME_TEXT_SIZE,
					color = if isOwned then nil else DIM_COLOR,
					size = UDim2.new(1, 0, 0, NAME_HEIGHT),
					position = UDim2.new(0.5, 0, 1, -10),
					anchorPoint = Vector2.new(0.5, 1),
				}),
			}),
		})
	end

	local rows = math.max(math.ceil(#reactions / TILES_PER_ROW), 1)

	return React.createElement(ui.Stack, {
		gap = ROW_GAP,
		fillHorizontal = true,
		size = UDim2.new(1, 0, 0, 0),
		automaticSize = Enum.AutomaticSize.Y,
	}, {
		BarHeader = header("Your bar", 1),
		Slots = React.createElement(ui.Row, {
			gap = TILE_GAP,
			horizontalAlignment = Enum.HorizontalAlignment.Left,
			size = UDim2.new(1, 0, 0, SLOT_SIZE),
			layoutOrder = 2,
		}, slotChildren),
		Hint = React.createElement(ui.Text, {
			text = if anyLocked
				then `Slot {selected} selected — pick a reaction below. Faded ones come from a pack in the shop.`
				else `Slot {selected} selected — pick a reaction below to put it there.`,
			textSize = HINT_TEXT_SIZE,
			color = DIM_COLOR,
			xAlignment = Enum.TextXAlignment.Left,
			wrapped = true,
			size = UDim2.new(1, 0, 0, HINT_HEIGHT),
			layoutOrder = 3,
		}),

		AllHeader = header("All reactions", 4),
		Grid = React.createElement(ui.Grid, {
			cellSize = UDim2.fromOffset(TILE_WIDTH, TILE_HEIGHT),
			cellPadding = UDim2.fromOffset(TILE_GAP, TILE_GAP),
			horizontalAlignment = Enum.HorizontalAlignment.Left,
			size = UDim2.new(1, 0, 0, rows * TILE_HEIGHT + (rows - 1) * TILE_GAP),
			layoutOrder = 5,
		}, tiles),
	})
end
