--!strict
-- The run: which day is claimable, what's already been claimed, and how long
-- until the next one opens. Pure functions over a saved slice and a timestamp —
-- no services, no Players, nothing to mock.
--
-- Shared on purpose. The client renders against exactly the arithmetic the
-- server validates with, so a card can't say "Claim" on a day the server will
-- refuse. The server is still the authority: it re-resolves at claim time and
-- ignores whatever the client thought.
--
-- Boundaries are **UTC midnight**, not "24h since your last claim". A rolling
-- 24h window punishes playing earlier in the day — claim at 9pm and tomorrow's
-- reward isn't there at 9am — which teaches players to claim later and later.
-- A calendar day means "come back tomorrow" is literally true.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Features.DailyRewards.Constants)

local SECONDS_PER_DAY = 86400

export type Saved = {
	-- Days claimed in the current run, 0..CYCLE_DAYS. Written by the server as
	-- the day it just granted, so it wraps to 1 rather than growing forever.
	Streak: number?,
	-- os.time() of the last claim. 0 = never claimed.
	LastClaim: number?,
}

export type State = {
	-- The day a claim would grant right now (1..CYCLE_DAYS), whether or not one
	-- is available yet.
	nextDay: number,
	-- False when today's reward is already taken.
	canClaim: boolean,
	-- Days of the *currently displayed* run that are done. Not the raw Streak:
	-- once the run wraps or breaks this is 0, so the grid doesn't show last
	-- week's ticks against this week's days.
	claimedThrough: number,
	-- The previous run ended because too many days were missed.
	broken: boolean,
	-- Until the next UTC midnight, i.e. until `canClaim` can flip to true.
	secondsUntilReset: number,
}

local Cycle = {}

-- Which UTC calendar day a timestamp falls in.
function Cycle.dayIndex(unixTime: number): number
	return math.floor(unixTime / SECONDS_PER_DAY)
end

function Cycle.resolve(saved: Saved?, now: number): State
	local streak = if saved and typeof(saved.Streak) == "number" then saved.Streak else 0
	local lastClaim = if saved and typeof(saved.LastClaim) == "number" then saved.LastClaim else 0
	local secondsUntilReset = (Cycle.dayIndex(now) + 1) * SECONDS_PER_DAY - now

	-- Never claimed: the run starts at day 1 and it's available now.
	if lastClaim <= 0 then
		return {
			nextDay = 1,
			canClaim = true,
			claimedThrough = 0,
			broken = false,
			secondsUntilReset = secondsUntilReset,
		}
	end

	local daysSince = Cycle.dayIndex(now) - Cycle.dayIndex(lastClaim)
	-- Missing more than the grace ends the run — back to day 1. A clock that
	-- went backwards (negative, from a server time correction) is treated as
	-- "same day" rather than as a broken run, because punishing a player for
	-- our clock would be the worse failure.
	local broken = daysSince > Constants.GRACE_DAYS
	if broken then
		return {
			nextDay = 1,
			canClaim = true,
			claimedThrough = 0,
			broken = true,
			secondsUntilReset = secondsUntilReset,
		}
	end

	-- Wraps: after the last day of a run the next claim starts a fresh one.
	local nextDay = (streak % Constants.CYCLE_DAYS) + 1
	local canClaim = daysSince > 0
	-- A fresh run shows no ticks. Without this, the day after finishing a run
	-- day 1 would read as both "claimed" (streak still 7) and "ready".
	local wrapped = canClaim and nextDay == 1

	return {
		nextDay = nextDay,
		canClaim = canClaim,
		claimedThrough = if wrapped then 0 else streak,
		broken = false,
		secondsUntilReset = secondsUntilReset,
	}
end

export type Status = "claimed" | "ready" | "locked"

-- What one card should draw. One source of truth for the grid and the grand
-- card, so they can't disagree about which day is live.
function Cycle.statusFor(day: number, state: State): Status
	if day <= state.claimedThrough then
		return "claimed"
	end
	if day == state.nextDay and state.canClaim then
		return "ready"
	end
	return "locked"
end

-- Coarse "5h 12m" / "12m" / "48s" for the countdown strip. Coarse on purpose —
-- a ticking second counter on a ~20 hour wait is noise.
function Cycle.formatDuration(seconds: number): string
	local remaining = math.max(0, math.floor(seconds))
	local hours = remaining // 3600
	local minutes = (remaining % 3600) // 60
	if hours > 0 then
		return `{hours}h {minutes}m`
	end
	if minutes > 0 then
		return `{minutes}m`
	end
	return `{remaining}s`
end

return Cycle
