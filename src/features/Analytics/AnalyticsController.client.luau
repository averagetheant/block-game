-- Client surface for Analytics. Sends steps up; logs nothing itself.
--
-- Roblox's analytics API is server-only, so this is a relay and deliberately
-- almost empty. What it buys over calling the packet directly from a view is
-- the same thing every other controller buys: the call site says what happened
-- ("the shop opened") instead of how it's reported, and a view stays a view —
-- `Packets.*` in a `.ui.luau` is exactly what tools/check-views fails on.
--
-- Steps are fire-and-forget. Nothing here waits, returns a result, or retries:
-- a lost telemetry packet costs one row on a dashboard, and any code path that
-- could block a click on an analytics call would be a worse bug than the
-- missing data.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Required for its side effect: loading Features.Analytics runs the discovery
-- loop that fills this realm's registry. Without it the client can still send
-- steps (the server resolves them), but `AnalyticsController.has` would answer
-- for an empty registry.
require(ReplicatedStorage.Features.Analytics)

local Constants = require(ReplicatedStorage.Features.Analytics.Constants)
local Packets = require(ReplicatedStorage.Features.Analytics.Packets)
local Registry = require(ReplicatedStorage.Features.Analytics.Registry)

local AnalyticsController = {}

local ENABLED = Constants.Presentations.client

-- Warned-about funnel/step pairs, so a mistyped step in a render path doesn't
-- print once a frame.
local warned: { [string]: boolean } = {}

-- Catch a bad step name on the realm that wrote it. The server would drop it
-- anyway, but it would drop it with a warn in the *server* log, which is not
-- where whoever typed it is looking.
local function known(funnelId: string, stepName: string): boolean
	if Registry.stepNumber(funnelId, stepName) ~= nil then
		return true
	end
	local key = `{funnelId}/{stepName}`
	if not warned[key] then
		warned[key] = true
		warn(`[Analytics] no step "{stepName}" in funnel "{funnelId}" — check the sibling Analytics.luau`)
	end
	return false
end

-- Log one step of a funnel already in progress.
function AnalyticsController.step(funnelId: string, stepName: string)
	if not ENABLED or not known(funnelId, stepName) then
		return
	end
	Packets.Step.send({ funnelId = funnelId, stepName = stepName, sessionId = "" })
end

-- Begin a fresh pass through a funnel and log its first step. Use this at the
-- point the journey starts — opening the shop, opening the daily window — so
-- the second visit is a second row rather than more steps on the first.
function AnalyticsController.start(funnelId: string, stepName: string)
	if not ENABLED or not known(funnelId, stepName) then
		return
	end
	Packets.Start.send({ funnelId = funnelId, stepName = stepName })
end

-- One step of the experience-wide onboarding funnel. The server dedupes against
-- the profile, so calling this on every join is correct and cheap — it fires
-- once per user, ever.
function AnalyticsController.onboarding(step: number)
	if not ENABLED then
		return
	end
	if step < Constants.MIN_STEP or step > Constants.MAX_STEP then
		warn(`[Analytics] onboarding step {step} is outside 1–{Constants.MAX_STEP}`)
		return
	end
	Packets.Onboarding.send({ step = step })
end

return AnalyticsController
