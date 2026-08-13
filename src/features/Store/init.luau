-- Store — the shop, the inventory, and the ownership both read.
--
-- Store owns no content. Features declare their packs, currencies, developer
-- products and gamepasses in a sibling `Store.luau` that the auto-discovery
-- loop below picks up on both realms; Store renders and validates whatever it
-- finds. See docs/game/Store.md.

local Store = {}

Store.Constants = require(script.Constants)
Store.Catalog = require(script.Catalog)
Store.ShopUI = require(script.ShopUI)
Store.InventoryUI = require(script.InventoryUI)

-- UIShell frame ids, so another feature can navigate the player to either
-- window: `UIShell.useFrame().open(Store.SHOP_FRAME_ID)`.
Store.SHOP_FRAME_ID = Store.Constants.SHOP_FRAME_ID
Store.INVENTORY_FRAME_ID = Store.Constants.INVENTORY_FRAME_ID

Store.registerKind = Store.Catalog.registerKind
Store.registerPack = Store.Catalog.registerPack
Store.registerCurrency = Store.Catalog.registerCurrency
Store.registerProduct = Store.Catalog.registerProduct
Store.registerGamepass = Store.Catalog.registerGamepass
Store.registerInventoryTab = Store.Catalog.registerInventoryTab

------------------------------------------------------------------------------
-- Auto-discovery
------------------------------------------------------------------------------
-- Walk the Features tree and require any sibling feature's `Store.luau`, which
-- returns `function(Store) … end`. Same convention as PlayerData / Settings /
-- Sidebar: the registering module never requires Features.Store itself, it
-- receives this table as an argument.
do
	local Features = script.Parent
	for _, featureModule in Features:GetChildren() do
		if featureModule == script then
			continue
		end
		local mod = featureModule:FindFirstChild("Store")
		if mod == nil or not mod:IsA("ModuleScript") then
			continue
		end

		local ok, result = pcall(require, mod)
		if not ok then
			warn(`[Store] failed to require {mod:GetFullName()}: {result}`)
			continue
		end
		if typeof(result) ~= "function" then
			warn(`[Store] {mod:GetFullName()} must return function(Store); got {typeof(result)}`)
			continue
		end

		local okCall, err = pcall(result, Store)
		if not okCall then
			warn(`[Store] registration error in {mod:GetFullName()}: {err}`)
		end
	end

	-- Discovery is the only sanctioned window for content the server validates
	-- against. Anything later would let the two realms' catalogs drift.
	Store.Catalog.seal()
end

return Store
