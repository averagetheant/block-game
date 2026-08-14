-- Reactions' day in the daily run. Discovered by
-- src/features/DailyRewards/init.luau at load time; see
-- docs/game/DailyRewards.md.
--
-- Midweek on purpose: day 4 is the furthest point from either end of the run,
-- so a reward that isn't more coins is what stops the middle of the week
-- reading as filler.
--
-- The "pack" kind this points at is registered by Store, which knows how to
-- mark a pack owned. Declarative only, so it loads on both realms.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local assets = require(ReplicatedStorage.Shared.Boil).assets
local Catalog = require(script.Parent.Catalog)
local Constants = require(script.Parent.Constants)

return function(DailyRewards)
	-- Nothing to hand out if the bar is switched off — the pack would be
	-- granted and there'd be nowhere to use it.
	if not Constants.Presentations.bar then
		return
	end

	DailyRewards.registerDay({
		day = 4,
		kind = "pack",
		payload = { packId = Catalog.HYPE_PACK_ID },
		name = "Hype Pack",
		icon = assets.Icons.friends,
	})
end
