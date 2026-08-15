--!strict
-- Every funnel the game reports, declared by the features that own the journey
-- rather than by Analytics itself.
--
-- Analytics ships the mechanism (session ids, sampling, throttling, the one
-- call into Roblox's AnalyticsService) and knows nothing about towers or shops.
-- A feature declares its funnels in a sibling `Analytics.luau`, which the
-- auto-discovery loop in init.luau requires on both realms:
--
--   -- src/features/Pets/Analytics.luau
--   return function(Analytics)
--       Analytics.registerFunnel({
--           id = "petHatch",
--           name = "Pet Hatch",
--           steps = { "Egg Opened", "Hatch Started", "Pet Received" },
--       })
--   end
--
-- Both realms register the same set, which matters for the same reason it does
-- in Store: the client reports steps by *name*, and the server refuses a step
-- it can't find in the registry — so a client-only funnel would report into
-- nothing, and a server-only one would drop every client-side step in it.
--
-- Steps are declared as an ordered list and referenced by name at the call
-- site. The number Roblox wants is the index, which means inserting a step in
-- the middle renumbers the ones after it automatically and no call site has to
-- know. (It also renumbers them on the dashboard, which is why `steps` is
-- append-only in practice — see docs/game/Analytics.md.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Packages.Signal)
local Constants = require(script.Parent.Constants)

export type Funnel = {
	-- Internal id. What call sites pass; never shown on the dashboard.
	id: string,
	-- The name Roblox files the funnel under. This is the string on the
	-- dashboard tab, so it reads as a title rather than an id.
	name: string,
	-- Ordered step names. Index = the step number Roblox is given.
	steps: { string },
	-- Fraction of funnel sessions to log, 0–1. Omitted means log everything;
	-- see Constants.TURN_SAMPLE_RATE for the one funnel that doesn't.
	sampleRate: number?,
	-- What one funnel session means, purely as documentation for whoever reads
	-- this next. The lifetime is enforced by whoever calls `startSession`.
	scope: string?,
}

export type OnboardingStep = {
	-- 1-based, and unique across every feature that registers one. Roblox's
	-- onboarding funnel is a single funnel for the whole experience, so these
	-- numbers are a shared space — hence the collision warn below.
	step: number,
	name: string,
}

local Registry = {}

-- Fires on every registration, so a late funnel is picked up by anything that
-- has already listed them.
Registry.Changed = Signal.new()

local funnels: { [string]: Funnel } = {}
local funnelOrder: { string } = {}
local onboarding: { [number]: OnboardingStep } = {}

local sealed = false

function Registry.seal()
	sealed = true
end

local function assertUnsealed(what: string, id: string | number)
	if not sealed then
		return
	end
	error(
		`[Analytics] {what} "{id}" registered after the registry was sealed. Register `
			.. `only from a sibling Analytics.luau picked up by auto-discovery — otherwise `
			.. `the client reports steps the server can't resolve.`,
		2
	)
end

function Registry.registerFunnel(def: Funnel)
	assertUnsealed("funnel", def.id)

	if funnels[def.id] ~= nil then
		warn(`[Analytics] funnel "{def.id}" already registered; overwriting`)
	else
		-- Roblox shows ten funnel tabs and ignores the rest. Silently. The
		-- eleventh funnel is not a smaller dashboard, it's a funnel that looks
		-- registered in code and produces no data at all, so it's worth a loud
		-- warn at load rather than a quiet gap a month later.
		if #funnelOrder >= Constants.MAX_FUNNELS then
			warn(
				`[Analytics] funnel "{def.id}" is number {#funnelOrder + 1}; Roblox `
					.. `reports at most {Constants.MAX_FUNNELS} and will ignore this one. `
					.. `Retire a funnel before adding another.`
			)
		end
		table.insert(funnelOrder, def.id)
	end

	if #def.steps == 0 then
		warn(`[Analytics] funnel "{def.id}" has no steps`)
	end
	if #def.steps > Constants.MAX_STEP then
		warn(`[Analytics] funnel "{def.id}" has {#def.steps} steps; Roblox caps a funnel at {Constants.MAX_STEP}`)
	end

	funnels[def.id] = def
	Registry.Changed:Fire()
end

-- One step of the experience-wide onboarding funnel. Separate from the ten
-- because Roblox's onboarding funnel is its own API and its own dashboard tab:
-- it fires once per *user* ever, not once per session, which is what makes it
-- the new-player retention view rather than a conversion view.
function Registry.registerOnboardingStep(def: OnboardingStep)
	assertUnsealed("onboarding step", def.step)

	if def.step < Constants.MIN_STEP or def.step > Constants.MAX_STEP then
		warn(`[Analytics] onboarding step {def.step} ("{def.name}") is outside 1–{Constants.MAX_STEP}; ignored`)
		return
	end
	local existing = onboarding[def.step]
	if existing ~= nil and existing.name ~= def.name then
		warn(
			`[Analytics] onboarding step {def.step} is registered twice, as "{existing.name}" `
				.. `and "{def.name}". The onboarding funnel is one shared funnel for the whole `
				.. `experience — pick distinct numbers.`
		)
	end

	onboarding[def.step] = def
	Registry.Changed:Fire()
end

-- Lookups ---------------------------------------------------------------------

function Registry.getFunnel(id: string): Funnel?
	return funnels[id]
end

-- The 1-based step number for a step name, or nil if the funnel doesn't have
-- one by that name. Call sites name their steps, so a typo is a nil here rather
-- than a step logged under the wrong number.
function Registry.stepNumber(funnelId: string, stepName: string): number?
	local funnel = funnels[funnelId]
	if funnel == nil then
		return nil
	end
	for index, name in funnel.steps do
		if name == stepName then
			return index
		end
	end
	return nil
end

function Registry.getOnboardingStep(step: number): OnboardingStep?
	return onboarding[step]
end

-- Registration order, which is also the order they were declared in across the
-- discovery pass. Only used for logging what got registered.
function Registry.listFunnels(): { Funnel }
	local result: { Funnel } = {}
	for _, id in funnelOrder do
		table.insert(result, funnels[id])
	end
	return result
end

function Registry.listOnboardingSteps(): { OnboardingStep }
	local result: { OnboardingStep } = {}
	for _, def in onboarding do
		table.insert(result, def)
	end
	table.sort(result, function(a, b)
		return a.step < b.step
	end)
	return result
end

return Registry
