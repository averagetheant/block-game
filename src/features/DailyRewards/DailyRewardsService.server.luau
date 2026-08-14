-- Server side of the daily run: the only place a claim is judged, a reward is
-- handed over, or a streak is written. The client says which day it thinks is
-- open; everything about whether it can have it happens here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Required for its side effect: loading Features.DailyRewards runs init.luau's
-- auto-discovery loop, which registers every feature's kinds and days into the
-- per-realm registry. Submodule requires (Constants, Cycle) do NOT trigger it,
-- so without this line the server's registry stays empty and every claim is
-- rejected.
require(ReplicatedStorage.Features.DailyRewards)

local Constants = require(ReplicatedStorage.Features.DailyRewards.Constants)
local Cycle = require(ReplicatedStorage.Features.DailyRewards.Cycle)
local Packets = require(ReplicatedStorage.Features.DailyRewards.Packets)
local Registry = require(ReplicatedStorage.Features.DailyRewards.Registry)
local PlayerDataService = require(ServerScriptService.Features.PlayerData.PlayerDataService)

local DailyRewardsService = {}

-- After PlayerData (1) and after Store (10), whose grant kinds this leans on
-- for currency and packs. Ordering is a nicety rather than a requirement — a
-- claim resolves the kind at claim time, not at start — but a player who joins
-- mid-boot shouldn't be the one to discover that.
DailyRewardsService.Priority = 15

local KEY = Constants.PROFILE_KEY

local function slice(player: Player): Cycle.Saved?
	local data = PlayerDataService.GetData(player)
	return if data then data[KEY] else nil
end

-- Where the run currently stands for this player, or nil if their profile
-- hasn't loaded. Public so another feature can ask "can they claim?" without
-- reimplementing the arithmetic.
function DailyRewardsService.state(player: Player): Cycle.State?
	local saved = slice(player)
	if saved == nil then
		return nil
	end
	return Cycle.resolve(saved, os.time())
end

-- The server-side core intent: judge, grant, then record. Every presentation
-- routes through here (the ByteNet packet from the window, the `claimdaily`
-- Cmdr command), so they share one validated path.
--
-- `expectedDay` is what the caller believes is open. Passing nil means "claim
-- whatever is open" — the command does that; the packet passes the day the
-- button was drawn with, so a window left open across midnight can't claim a
-- day the player never saw.
--
-- Returns (granted, message). The message is for the command and the log; the
-- window learns the outcome from the replica diff.
function DailyRewardsService.claim(player: Player, expectedDay: number?): (boolean, string)
	local saved = slice(player)
	if saved == nil then
		return false, "Your profile is still loading."
	end

	local now = os.time()
	local state = Cycle.resolve(saved, now)
	if not state.canClaim then
		return false, `Already claimed today. Next in {Cycle.formatDuration(state.secondsUntilReset)}.`
	end
	if expectedDay ~= nil and expectedDay ~= state.nextDay then
		-- Not an error worth logging loudly: a window open across a UTC
		-- midnight lands here honestly. Refuse rather than silently granting a
		-- different day than the one whose button was pressed.
		return false, `Day {expectedDay} isn't the one that's open (day {state.nextDay} is).`
	end

	local day = Registry.getDay(state.nextDay)
	if day == nil then
		warn(`[DailyRewards] day {state.nextDay} has no registered reward; nothing to grant`)
		return false, `Day {state.nextDay} has no reward configured.`
	end

	local kind = Registry.getKind(day.kind)
	if kind == nil then
		warn(`[DailyRewards] day {state.nextDay} wants kind "{day.kind}", which nothing registered`)
		return false, `Day {state.nextDay}'s reward type isn't available.`
	end

	-- Grant BEFORE recording. A grant that throws or declines leaves the day
	-- open, which is the right way round to fail: a player who lost a reward to
	-- our bug can retry, whereas a burned streak day is unrecoverable.
	local ok, granted = pcall(kind.grant, player, day.payload)
	if not ok then
		warn(`[DailyRewards] kind "{day.kind}" errored granting day {state.nextDay} to {player.Name}: {granted}`)
		return false, "That reward couldn't be granted just now."
	end
	if granted ~= true then
		return false, "That reward couldn't be granted just now."
	end

	-- Blessed mutation path: replica + profile stay in sync, and the diff is
	-- what re-renders the window.
	PlayerDataService.SetValue(player, { KEY, "Streak" }, state.nextDay)
	PlayerDataService.SetValue(player, { KEY, "LastClaim" }, now)

	return true, `Claimed day {state.nextDay}: {day.name}.`
end

function DailyRewardsService.Start()
	Packets.Claim.listen(function(payload, player)
		local day = payload.day
		-- ByteNet decoded it as a uint8, so this only rules out a client
		-- sending a number outside the run at all.
		if day < 1 or day > Constants.MAX_DAY then
			return
		end
		DailyRewardsService.claim(player, day)
	end)

	-- No PlayerAdded hook on purpose. The obvious one — reset a broken streak
	-- at join — would be a profile write on every login for something
	-- `Cycle.resolve` already derives from LastClaim on both realms.
end

return DailyRewardsService
