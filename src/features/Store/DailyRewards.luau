-- How Store's two kinds of thing get handed over as a daily reward. Discovered
-- by src/features/DailyRewards/init.luau at load time; see
-- docs/game/DailyRewards.md.
--
-- Kinds only — no days. Store owns *how* to credit a currency and *how* to mark
-- a pack owned, but it doesn't own the coins (TowerGame does) and it doesn't
-- decide what day 3 gives. The features whose content it is schedule their own
-- days and point them at these kinds.
--
-- This module loads on both realms, which is why the grant bodies do their
-- ServerScriptService require inside the function: the registry only stores the
-- closure, and only the server ever calls it. Same trick as a Cmdr `Run`.

return function(DailyRewards)
	-- payload: { currency = <registered currency id>, amount = <number> }
	DailyRewards.registerKind({
		id = "currency",
		grant = function(player, payload)
			if typeof(payload) ~= "table" then
				return false
			end
			if typeof(payload.currency) ~= "string" or typeof(payload.amount) ~= "number" then
				return false
			end

			local ServerScriptService = game:GetService("ServerScriptService")
			local StoreService = require(ServerScriptService.Features.Store.StoreService)
			-- Declines on an unregistered currency or an unloaded profile,
			-- which leaves the day claimable rather than burning it.
			return StoreService.credit(player, payload.currency, payload.amount)
		end,
	})

	-- payload: { packId = <registered pack id> }
	DailyRewards.registerKind({
		id = "pack",
		grant = function(player, payload)
			if typeof(payload) ~= "table" or typeof(payload.packId) ~= "string" then
				return false
			end

			local ServerScriptService = game:GetService("ServerScriptService")
			local StoreService = require(ServerScriptService.Features.Store.StoreService)
			-- Already owning it counts as granted — see StoreService.grantPack.
			return StoreService.grantPack(player, payload.packId)
		end,
	})
end
