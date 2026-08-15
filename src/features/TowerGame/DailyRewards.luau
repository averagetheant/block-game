-- TowerGame's days in the daily run. Discovered by
-- src/features/DailyRewards/init.luau at load time; see
-- docs/game/DailyRewards.md.
--
-- Coins are TowerGame's — earned by the tower, kept in TowerGame's profile
-- slice — so scheduling them is TowerGame's call, not the DailyRewards
-- feature's. The grand prize is a skin pack for the same reason: this folder
-- owns the skins.
--
-- The "currency" and "pack" kinds these point at are registered by Store, which
-- knows how to move a balance and how to mark a pack owned. Declarative only,
-- so it loads happily on both realms.

local Constants = require(script.Parent.Constants)
local SkinPacks = require(script.Parent.SkinPacks)

local CASH_ICON = Constants.CASH_IMAGE

-- The pack the last day hands over. Looked up in the list rather than described
-- again here: the name, the icon and the id all come from the one definition,
-- so the card can't advertise something the grant doesn't hand over. If the id
-- ever goes away this resolves to nil and the day simply isn't registered,
-- which the window draws as "???" — a visible hole beats a grand prize the
-- server silently refuses.
local GRAND_PACK_ID = "skins.needoh"

local function findPack(packId: string)
	for _, pack in SkinPacks.List do
		if pack.id == packId then
			return pack
		end
	end
	return nil
end

-- Escalating, and deliberately not linear: the jump from day 5 to 6 is what
-- makes the sixth day feel like the run is nearly done.
local COIN_DAYS = {
	{ day = 1, amount = 100 },
	{ day = 2, amount = 150 },
	{ day = 3, amount = 250 },
	{ day = 5, amount = 500 },
	{ day = 6, amount = 750 },
}

return function(DailyRewards)
	for _, entry in COIN_DAYS do
		DailyRewards.registerDay({
			day = entry.day,
			kind = "currency",
			payload = { currency = Constants.CURRENCY_ID, amount = entry.amount },
			-- Short by necessity: the name is drawn over the card art at the
			-- Large tier inside ~180px (see DailyRewardsUI).
			name = `{entry.amount} Coins`,
			icon = CASH_ICON,
		})
	end

	local grand = findPack(GRAND_PACK_ID)
	if grand == nil then
		warn(`[TowerGame] daily grand prize "{GRAND_PACK_ID}" is not in SkinPacks.List`)
		return
	end

	DailyRewards.registerDay({
		day = DailyRewards.Constants.CYCLE_DAYS,
		kind = "pack",
		payload = { packId = grand.id },
		name = grand.name,
		icon = grand.icon,
		caption = "Grand prize",
	})
end
