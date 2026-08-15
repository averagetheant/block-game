-- The only place in the game that calls Roblox's AnalyticsService.
--
-- Everything else — the tower, the shop, the daily run — reports in terms of
-- its own journey ("the shop funnel reached Granted") and this translates that
-- into the numbered step events Roblox wants. Two reasons it's centralised
-- rather than sprinkled:
--
--   * Roblox's funnel API is positional and unforgiving. `step` is an integer
--     whose meaning lives on a dashboard, and passing 4 where you meant 5 is a
--     mistake nothing catches — not the type checker, not a test, not the
--     dashboard, which happily renders the wrong funnel. Resolving names to
--     numbers in one place against a registry both realms share is the only
--     way that mistake becomes impossible instead of merely unlikely.
--   * Analytics must never be able to break the game. Every call into Roblox
--     from here is wrapped, throttled and gated, so the worst a bad funnel can
--     do is lose its own data.
--
-- Sampling and dedupe both live at the *session* level, not the step level.
-- See `startSession`.

local AnalyticsService_Roblox = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Required for its side effect: loading Features.Analytics runs init.luau's
-- auto-discovery loop, which registers every feature's funnels into the
-- per-realm registry. Submodule requires (Constants, Registry) do NOT trigger
-- it, so without this line the server's registry stays empty and every step is
-- dropped as unregistered.
require(ReplicatedStorage.Features.Analytics)

local Constants = require(ReplicatedStorage.Features.Analytics.Constants)
local Packets = require(ReplicatedStorage.Features.Analytics.Packets)
local Registry = require(ReplicatedStorage.Features.Analytics.Registry)
local PlayerDataService = require(ServerScriptService.Features.PlayerData.PlayerDataService)

local AnalyticsService = {}

-- After PlayerData (1) and ahead of the feature services that fire steps, so a
-- step fired from another service's Start has somewhere to land. Nothing breaks
-- if it doesn't — an early step is dropped with a warn, not an error.
AnalyticsService.Priority = 5

local KEY = "Analytics"
local ENABLED = Constants.Presentations.service

-- player → funnelId → the session currently open for that funnel.
type Session = {
	id: string,
	-- Decided once, when the session opens. See startSession.
	sampled: boolean,
	-- Step numbers already logged in this session, so a step fired twice counts
	-- once. A funnel step is "did the player get this far", not "how many times
	-- did this code run" — and the two diverge constantly in practice (a retry,
	-- a re-render, a packet the client sent twice).
	seen: { [number]: boolean },
}
local sessions: { [Player]: { [string]: Session } } = {}

-- player → events logged in the current minute, and when that minute started.
local budget: { [Player]: { count: number, since: number } } = {}

-- Guard rails ------------------------------------------------------------------

-- Is this player someone we log for at all. Cheap, and free of side effects —
-- the budget is only spent by `spend` below.
local function active(player: Player): boolean
	if not ENABLED then
		return false
	end
	-- A player who left mid-flight. Roblox rejects the call anyway; this keeps
	-- it out of the log.
	return player ~= nil and player.Parent == Players
end

-- Take one event out of this player's minute. Call this *last*, immediately
-- before logging, never as a guard at the top of a function.
--
-- The distinction matters more than it looks. `step` is called from the aim
-- stream, which runs at 30Hz for whoever is holding a piece: nearly all of
-- those calls are deduped away as steps already reached, and if each one spent
-- a budget event first, one player aiming would exhaust the whole minute's
-- allowance in four seconds and every real event in the server would be
-- dropped behind it.
local function spend(player: Player): boolean
	local now = os.clock()
	local used = budget[player]
	if used == nil or now - used.since >= 60 then
		budget[player] = { count = 1, since = now }
		return true
	end

	used.count += 1
	if used.count > Constants.MAX_EVENTS_PER_MINUTE then
		-- Warn once on the event that crosses the line, not on all of them —
		-- the whole failure mode being guarded against is a loop, and a warn
		-- per iteration would be its own version of the same problem.
		if used.count == Constants.MAX_EVENTS_PER_MINUTE + 1 then
			warn(
				`[Analytics] {player.Name} exceeded {Constants.MAX_EVENTS_PER_MINUTE} events/minute; `
					.. `dropping the rest of this minute. Something is firing steps in a loop.`
			)
		end
		return false
	end
	return true
end

-- Custom fields are three positional slots on Roblox's side, keyed
-- CustomField01..03. Callers pass a plain list of values and get them mapped in
-- order, because the alternative — every call site spelling out
-- ["CustomField02"] — puts the slot numbering into forty places instead of one.
local function fields(values: { string }?): { [string]: string }?
	if values == nil or #values == 0 then
		return nil
	end
	local mapped: { [string]: string } = {}
	for index, value in values do
		local key = Constants.CUSTOM_FIELD_KEYS[index]
		if key == nil then
			warn(`[Analytics] dropped custom field {index} ("{value}"); Roblox allows {Constants.MAX_CUSTOM_FIELDS}`)
			break
		end
		mapped[key] = tostring(value)
	end
	return mapped
end

-- Every call into Roblox goes through here. A failure is logged and swallowed:
-- the analytics backend being unhappy is not a reason for a turn to end.
local function log(what: string, fn: (...any) -> (), ...: any)
	local ok, err = pcall(fn, ...)
	if not ok then
		warn(`[Analytics] {what} failed: {err}`)
	end
end

-- Sessions ---------------------------------------------------------------------

-- Open a fresh pass through a funnel and return its id.
--
-- Two things are decided here and nowhere else:
--
--   * the session id, which is what makes "one visit to the shop" a row on the
--     dashboard rather than a player's shop visits all collapsing together;
--   * whether this session is sampled at all. Deciding once per session is the
--     whole trick — a per-step coin flip on a 10%-sampled funnel would keep
--     step 2 and drop step 3 of the same session, and the dashboard would read
--     that as 90% of players abandoning the funnel at step 3.
--
-- `id` overrides the generated GUID, for the funnels whose "one pass" outlives
-- the server session it started in. The daily run is the case that needs it: a
-- seven-day journey has to carry the same id across seven joins, so it's keyed
-- by the run rather than generated fresh — Roblox's own guidance for funnels on
-- that timescale. A generated GUID is right for everything else.
function AnalyticsService.startSession(player: Player, funnelId: string, id: string?): string?
	if not ENABLED then
		return nil
	end
	local funnel = Registry.getFunnel(funnelId)
	if funnel == nil then
		warn(`[Analytics] startSession for unregistered funnel "{funnelId}"`)
		return nil
	end

	local open = sessions[player]
	if open == nil then
		-- They left, or never fully joined.
		return nil
	end

	local rate = funnel.sampleRate or Constants.DEFAULT_SAMPLE_RATE
	local session: Session = {
		id = id or HttpService:GenerateGUID(false),
		sampled = rate >= 1 or math.random() < rate,
		seen = {},
	}
	open[funnelId] = session
	return session.id
end

-- The session a step should be filed under. A step fired with no session open
-- opens one — a funnel whose first step was missed is still worth having, and
-- the alternative is dropping every step after a lost packet.
local function sessionFor(player: Player, funnelId: string): Session?
	local open = sessions[player]
	if open == nil then
		return nil
	end
	if open[funnelId] == nil then
		AnalyticsService.startSession(player, funnelId)
	end
	return open[funnelId]
end

-- Close a funnel session so the next step opens a fresh one. Called when a
-- journey ends in a way the next one shouldn't be grouped with: the shop
-- window closing, a round ending.
function AnalyticsService.endSession(player: Player, funnelId: string)
	local open = sessions[player]
	if open ~= nil then
		open[funnelId] = nil
	end
end

-- Funnels -----------------------------------------------------------------------

-- Log one step of one funnel, by name.
--
-- `custom` is up to three strings, mapped onto Roblox's CustomField01..03 in
-- order. Keep them low-cardinality — Roblox tracks 8,000 unique field
-- combinations per experience and a user id in a custom field burns that in an
-- afternoon.
function AnalyticsService.step(player: Player, funnelId: string, stepName: string, custom: { string }?)
	if not active(player) then
		return
	end

	local funnel = Registry.getFunnel(funnelId)
	if funnel == nil then
		warn(`[Analytics] step "{stepName}" for unregistered funnel "{funnelId}"`)
		return
	end
	local step = Registry.stepNumber(funnelId, stepName)
	if step == nil then
		warn(`[Analytics] funnel "{funnelId}" has no step named "{stepName}"`)
		return
	end

	local session = sessionFor(player, funnelId)
	if session == nil then
		return
	end
	if not session.sampled then
		return
	end
	-- Already reached this step in this pass. See Session.seen. This is the
	-- check that makes calling `step` from a hot loop safe, so it stays ahead
	-- of `spend`.
	if session.seen[step] then
		return
	end
	if not spend(player) then
		return
	end
	session.seen[step] = true

	log(`funnel "{funnelId}" step {step}`, function()
		AnalyticsService_Roblox:LogFunnelStepEvent(player, funnel.name, session.id, step, stepName, fields(custom))
	end)
end

-- Open a session and log its first step in one call — the shape almost every
-- journey actually starts with.
function AnalyticsService.start(player: Player, funnelId: string, stepName: string, custom: { string }?)
	AnalyticsService.endSession(player, funnelId)
	AnalyticsService.startSession(player, funnelId)
	AnalyticsService.step(player, funnelId, stepName, custom)
end

-- Onboarding ---------------------------------------------------------------------

-- One step of the experience-wide onboarding funnel, fired at most once per
-- user ever. See PlayerData.luau for why the high-water mark is persisted.
function AnalyticsService.onboarding(player: Player, step: number)
	if not active(player) then
		return
	end

	local def = Registry.getOnboardingStep(step)
	if def == nil then
		warn(`[Analytics] onboarding step {step} was never registered`)
		return
	end

	local data = PlayerDataService.GetData(player)
	local saved = if data then data[KEY] else nil
	-- No profile yet: skip rather than fire. Firing now and persisting nothing
	-- would double-count them on their next join, which is the one thing this
	-- funnel must not do.
	if saved == nil then
		return
	end
	local reached = if typeof(saved.Onboarding) == "number" then saved.Onboarding else 0
	-- Same ordering as `step`: onboarding is fired from gameplay paths that run
	-- constantly (every drop calls step 3), and all but the first are deduped
	-- here rather than costing an event.
	if step <= reached then
		return
	end
	if not spend(player) then
		return
	end

	PlayerDataService.SetValue(player, { KEY, "Onboarding" }, step)
	log(`onboarding step {step}`, function()
		AnalyticsService_Roblox:LogOnboardingFunnelStepEvent(player, step, def.name)
	end)
end

-- Economy -------------------------------------------------------------------------

-- A coin moving in or out. `flow` is "source" or "sink" as plain text, because
-- every call site reads better that way than with a full enum path; the enum is
-- resolved here.
--
-- `endingBalance` is the balance *after* the move, which is Roblox's ask and
-- the reason this is called after the write rather than before it.
function AnalyticsService.economy(
	player: Player,
	flow: "source" | "sink",
	amount: number,
	endingBalance: number,
	transactionType: string,
	itemSku: string?
)
	-- Amount first: a zero-coin award is a no-op the caller shouldn't have to
	-- filter, and it shouldn't cost an event either.
	if amount <= 0 then
		return
	end
	if not active(player) or not spend(player) then
		return
	end

	-- The enum lookup is inside the closure, not above it. Indexing a member
	-- Roblox has renamed throws, and out here that throw would land in whatever
	-- gameplay path paid the coins out — this file's whole premise is that a
	-- broken analytics call costs its own data and nothing else.
	log(`economy {flow} {amount}`, function()
		AnalyticsService_Roblox:LogEconomyEvent(
			player,
			if flow == "sink" then Enum.AnalyticsEconomyFlowType.Sink else Enum.AnalyticsEconomyFlowType.Source,
			Constants.CURRENCY_COINS,
			amount,
			endingBalance,
			transactionType,
			itemSku
		)
	end)
end

-- Progression -----------------------------------------------------------------------

-- A checkpoint started, cleared, or lost to the storm. `status` is "start",
-- "complete" or "fail".
function AnalyticsService.progression(player: Player, status: "start" | "complete" | "fail", level: number, levelName: string)
	if not active(player) or not spend(player) then
		return
	end

	-- Inside the closure for the same reason as `economy` above.
	log(`progression {status} {level}`, function()
		local progressionType = if status == "complete"
			then Enum.AnalyticsProgressionType.Complete
			elseif status == "fail" then Enum.AnalyticsProgressionType.Fail
			else Enum.AnalyticsProgressionType.Start

		AnalyticsService_Roblox:LogProgressionEvent(
			player,
			Constants.PROGRESSION_PATH,
			progressionType,
			level,
			levelName
		)
	end)
end

-- Custom -------------------------------------------------------------------------

-- Anything that isn't a funnel, an economy move or a progression beat. Used for
-- the counts worth having without a journey attached — a reaction sent, a
-- gamemode won.
function AnalyticsService.custom(player: Player, eventName: string, value: number?, custom: { string }?)
	if not active(player) or not spend(player) then
		return
	end
	log(`custom event "{eventName}"`, function()
		AnalyticsService_Roblox:LogCustomEvent(player, eventName, value, fields(custom))
	end)
end

-- Client-reported steps ------------------------------------------------------------

local function onStep(payload: { funnelId: string, stepName: string, sessionId: string }, player: Player)
	if not Constants.Presentations.client then
		return
	end
	-- Nothing is trusted here beyond "this player is claiming this step". The
	-- funnel id and step name are resolved against the registry, which is what
	-- makes a made-up step a dropped event rather than a corrupt one, and the
	-- throttle in `allow` is what makes a client spamming steps a capped cost.
	AnalyticsService.step(player, payload.funnelId, payload.stepName)
end

local function onStart(payload: { funnelId: string, stepName: string }, player: Player)
	if not Constants.Presentations.client then
		return
	end
	AnalyticsService.start(player, payload.funnelId, payload.stepName)
end

local function onOnboarding(payload: { step: number }, player: Player)
	if not Constants.Presentations.client then
		return
	end
	AnalyticsService.onboarding(player, payload.step)
end

-- The session funnel ----------------------------------------------------------------

-- Elapsed-time steps of the `session` funnel, as { minutes, step name }. Driven
-- from here rather than from a feature because the funnel is Analytics' own —
-- see the registration in init.luau.
local SESSION_MARKS: { { minutes: number, name: string } } = {
	{ minutes = 1, name = "1 Minute" },
	{ minutes = 5, name = "5 Minutes" },
	{ minutes = 15, name = "15 Minutes" },
	{ minutes = 30, name = "30 Minutes" },
	{ minutes = 60, name = "60 Minutes" },
}

-- One thread per player rather than one polling loop over everyone: it sleeps
-- between marks instead of waking every second to compare timestamps, and it
-- ends by itself when the player leaves (the `sessions` entry is gone, so
-- `step` no-ops and the loop breaks).
local function driveSession(player: Player)
	AnalyticsService.start(player, "session", "Joined")

	local elapsed = 0
	for _, mark in SESSION_MARKS do
		task.wait((mark.minutes - elapsed) * 60)
		elapsed = mark.minutes
		if sessions[player] == nil then
			return
		end
		AnalyticsService.step(player, "session", mark.name)
	end
end

-- Onboarding step 1. Held until the profile lands, because `onboarding` refuses
-- to fire without one — firing before the write could persist would double-count
-- this user on their next join, and step 1 is the denominator the whole funnel
-- is measured against.
local function countArrival(player: Player)
	for _ = 1, 60 do
		if sessions[player] == nil then
			return
		end
		if PlayerDataService.GetData(player) ~= nil then
			AnalyticsService.onboarding(player, 1)
			return
		end
		task.wait(1)
	end
	warn(`[Analytics] {player.Name}'s profile never loaded; they are missing from the onboarding funnel`)
end

-- Lifecycle -------------------------------------------------------------------------

local function trackPlayer(player: Player)
	sessions[player] = {}
	budget[player] = { count = 0, since = os.clock() }

	task.spawn(driveSession, player)
	task.spawn(countArrival, player)
end

function AnalyticsService.Start()
	if not ENABLED then
		return
	end

	for _, player in Players:GetPlayers() do
		trackPlayer(player)
	end
	Players.PlayerAdded:Connect(trackPlayer)
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
		budget[player] = nil
	end)

	Packets.Step.listen(onStep)
	Packets.Start.listen(onStart)
	Packets.Onboarding.listen(onOnboarding)
end

return AnalyticsService
