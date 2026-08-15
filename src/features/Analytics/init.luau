-- Analytics — the funnels, and the one place Roblox's AnalyticsService is called.
--
-- Analytics owns no journeys. A feature declares the funnels it cares about in
-- a sibling `Analytics.luau` that the discovery loop below picks up on both
-- realms — the same convention PlayerData / Settings / Store / Sidebar /
-- Gamemode / DailyRewards use — and fires their steps from its own code. So
-- this folder names no other feature, and "what a conversion looks like" lives
-- with the feature being converted.
--
-- Two realms, two entry points, one registry:
--
--   server  AnalyticsService.step(player, "shop", "Pack Granted")
--   client  AnalyticsController.step("shop", "Pack Selected")
--
-- The client's call is a packet the server resolves and logs; Roblox's
-- analytics API is server-only. See docs/game/Analytics.md.

local Analytics = {}

Analytics.Constants = require(script.Constants)

local Registry = require(script.Registry)
Analytics.registerFunnel = Registry.registerFunnel
Analytics.registerOnboardingStep = Registry.registerOnboardingStep
Analytics.getFunnel = Registry.getFunnel
Analytics.stepNumber = Registry.stepNumber
Analytics.listFunnels = Registry.listFunnels
Analytics.listOnboardingSteps = Registry.listOnboardingSteps
Analytics.Changed = Registry.Changed

------------------------------------------------------------------------------
-- The one funnel Analytics owns
------------------------------------------------------------------------------
-- Every other funnel belongs to the feature whose journey it measures, and this
-- file names none of them. The session funnel is the exception because it isn't
-- about a journey at all: its steps are minutes elapsed, it would read the same
-- in a game with no tower and no shop, and there is no feature it could sensibly
-- be homed in. A feature naming *itself* is fine.
--
-- Registered before discovery so it takes slot 1 of Roblox's ten and a feature
-- that registers an eleventh gets the warn instead of silently displacing this.
Registry.registerFunnel({
	id = "session",
	name = "Play Session",
	scope = "One visit to the server, from join to leave.",
	steps = {
		"Joined",
		"1 Minute",
		"5 Minutes",
		"15 Minutes",
		"30 Minutes",
		"60 Minutes",
	},
})

-- Step 1 of the onboarding funnel, for the same reason: "they arrived" is not
-- TowerGame's fact. Steps 2–4 are TowerGame's, 5–6 are Store's — the allocation
-- table is in docs/game/Analytics.md.
Registry.registerOnboardingStep({ step = 1, name = "Joined" })

------------------------------------------------------------------------------
-- Auto-discovery
------------------------------------------------------------------------------
-- Walk the Features tree and require any sibling feature's `Analytics.luau`,
-- which returns `function(Analytics) … end`. The registering module never
-- requires Features.Analytics itself (that would be circular) — it receives
-- this table as an argument.
do
	local Features = script.Parent
	for _, featureModule in Features:GetChildren() do
		if featureModule == script then
			continue
		end
		local mod = featureModule:FindFirstChild("Analytics")
		if mod == nil or not mod:IsA("ModuleScript") then
			continue
		end

		local ok, result = pcall(require, mod)
		if not ok then
			warn(`[Analytics] failed to require {mod:GetFullName()}: {result}`)
			continue
		end
		if typeof(result) ~= "function" then
			warn(`[Analytics] {mod:GetFullName()} must return function(Analytics); got {typeof(result)}`)
			continue
		end

		local okCall, err = pcall(result, Analytics)
		if not okCall then
			warn(`[Analytics] registration error in {mod:GetFullName()}: {err}`)
		end
	end

	-- Discovery is the only sanctioned window. A funnel registered later would
	-- exist on one realm and not the other, and every client-reported step in
	-- it would be dropped by a server that never heard of it.
	Registry.seal()
end

return Analytics
