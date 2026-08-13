--!strict
-- Buyable block looks. One entry here becomes one card in the shop's Skins tab
-- and one equippable pack in the inventory — Store.luau reads this list, and so
-- does TowerSkinController, so the price and the material can't drift apart.
--
-- A skin pack overrides the *material* of every block on the owner's screen,
-- including whatever the current zone had dressed them in. That's the whole
-- product: Retro turns the tower into grey studded bricks, and a neon tower
-- stays neon through it.
--
-- It's a local override, not a server one. The tower is shared, so a cosmetic
-- one player bought can't be allowed to change what the room sees — everyone
-- else keeps seeing the server's materials.
--
-- `id` is a Store pack id and is persisted on the profile: append, don't rename.

export type SkinPack = {
	id: string,
	name: string,
	description: string,
	icon: string?,
	price: number,
	currency: string,
	variant: string?,
	order: number?,
	-- What every block part becomes while this pack is equipped.
	material: Enum.Material,
}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local assets = require(ReplicatedStorage.Shared.Boil).assets
local Constants = require(script.Parent.Constants)

local SkinPacks = {}

-- The Store pack kind these register under.
SkinPacks.KIND = "skin"

SkinPacks.List = {
	{
		id = "skins.neon",
		name = "Neon Blocks",
		description = "Every block glows. Overrides zone materials — a Retro zone can't dull it.",
		icon = assets.Icons.rocket,
		price = 100,
		currency = Constants.CURRENCY_ID,
		variant = "blue",
		order = 1,
		material = Enum.Material.Neon,
	},
} :: { SkinPack }

local byId: { [string]: SkinPack } = {}
for _, pack in SkinPacks.List do
	byId[pack.id] = pack
end

function SkinPacks.get(id: string?): SkinPack?
	if id == nil then
		return nil
	end
	return byId[id]
end

return SkinPacks
