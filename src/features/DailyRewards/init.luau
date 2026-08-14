-- DailyRewards — come back tomorrow, get the next thing.
--
-- A run of `Constants.CYCLE_DAYS` days. Claim one per UTC day to advance;
-- miss more than the grace and the run starts over. The last day is the grand
-- prize and gets the tall card.
--
-- This feature owns no rewards. A feature declares how to hand its content over
-- (a *kind*) and what sits on which day in a sibling `DailyRewards.luau` that
-- the discovery loop below picks up on both realms — the same convention
-- PlayerData / Settings / Store / Sidebar / Gamemode use. So this folder names
-- no other feature, and coins live in TowerGame.
--
-- See docs/game/DailyRewards.md for the flow, the wire format, and how to add
-- a reward type.

local DailyRewards = {}

DailyRewards.Constants = require(script.Constants)
DailyRewards.Cycle = require(script.Cycle)
DailyRewards.Layout = require(script.Layout)
DailyRewards.UI = require(script.DailyRewardsUI)

DailyRewards.FRAME_ID = DailyRewards.Constants.FRAME_ID

local Registry = require(script.Registry)
DailyRewards.registerKind = Registry.registerKind
DailyRewards.registerDay = Registry.registerDay
DailyRewards.getKind = Registry.getKind
DailyRewards.getDay = Registry.getDay
DailyRewards.listDays = Registry.listDays
DailyRewards.Changed = Registry.Changed

------------------------------------------------------------------------------
-- Auto-discovery
------------------------------------------------------------------------------
-- Walk the Features tree and require any sibling feature's `DailyRewards.luau`,
-- which returns `function(DailyRewards) … end`. The registering module never
-- requires Features.DailyRewards itself (that would be circular) — it receives
-- this table as an argument.
do
	local Features = script.Parent
	for _, featureModule in Features:GetChildren() do
		if featureModule == script then
			continue
		end
		local mod = featureModule:FindFirstChild("DailyRewards")
		if mod == nil or not mod:IsA("ModuleScript") then
			continue
		end

		local ok, result = pcall(require, mod)
		if not ok then
			warn(`[DailyRewards] failed to require {mod:GetFullName()}: {result}`)
			continue
		end
		if typeof(result) ~= "function" then
			warn(`[DailyRewards] {mod:GetFullName()} must return function(DailyRewards); got {typeof(result)}`)
			continue
		end

		local okCall, err = pcall(result, DailyRewards)
		if not okCall then
			warn(`[DailyRewards] registration error in {mod:GetFullName()}: {err}`)
		end
	end

	-- Discovery is the only sanctioned window for content the server validates
	-- against. Anything later would let the two realms' runs drift.
	Registry.seal()
end

return DailyRewards
