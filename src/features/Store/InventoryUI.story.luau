--!nonstrict
-- UI Labs story for the inventory body. Ownership is a control because it comes
-- from the replica in game; the "None" card is always there, so the empty case
-- is what you see with `ownEverything` off.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Features = ReplicatedStorage:WaitForChild("Features")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local ui = require(ReplicatedStorage.Shared.Boil).ui

local Store = require(Features:WaitForChild("Store"))

return {
	summary = "Inventory window: a tab per registered pack kind (equip one, or None) plus any tab a feature registered for itself. Toggle `ownEverything` to fill the grid; equipping only prints here — there's no replica in UI Labs.",
	react = React,
	reactRoblox = ReactRoblox,

	controls = {
		ownEverything = true,
	},

	story = function(props)
		local owned = {}
		if props.controls.ownEverything then
			for _, pack in Store.Catalog.listPacks() do
				owned[pack.id] = true
			end
		end

		local equipped, setEquipped = React.useState({})

		return React.createElement(ui.Window, {
			title = "Inventory",
			icon = ui.assets.Icons.book,
			titleVariant = "green",
			size = UDim2.fromOffset(820, 600),
		}, {
			Content = React.createElement(Store.InventoryUI, {
				owned = owned,
				equipped = equipped,
				onEquip = function(kind, packId)
					setEquipped(function(current)
						local next = table.clone(current)
						next[kind] = packId
						return next
					end)
				end,
				onUnequip = function(kind)
					setEquipped(function(current)
						local next = table.clone(current)
						next[kind] = nil
						return next
					end)
				end,
			}),
		})
	end,
}
