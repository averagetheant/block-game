-- Command presentation for DailyRewards (seam #4: a Cmdr command instead of a
-- screen GUI). `claimdaily` routes to the SAME server-side core intent the
-- window's packet routes to — DailyRewardsService.claim — so both surfaces are
-- judged by one validated path. `dailystatus` is read-only.
--
-- Shared module, discovered by the Cmdr feature on BOTH realms: the server
-- registers this with `Run`, the client registers it without so the console
-- accepts the name. See src/features/Cmdr/CommandRegistry.luau for why. The
-- server-realm require lives inside Run, which only executes on the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Features.DailyRewards.Constants)

if not Constants.Presentations.command then
	return {}
end

return {
	{
		Name = "claimdaily",
		Aliases = {},
		Description = "Claim today's daily reward, if one is open.",
		Group = "DailyRewards",
		Args = {},
		Run = function(context)
			local ServerScriptService = game:GetService("ServerScriptService")
			local DailyRewardsService =
				require(ServerScriptService.Features.DailyRewards.DailyRewardsService)
			-- No expected day: the command claims whatever is open, unlike the
			-- window, which passes the day its button was drawn with.
			local _, message = DailyRewardsService.claim(context.Executor, nil)
			return message
		end,
	},
	{
		Name = "dailystatus",
		Aliases = {},
		Description = "Show where you are in the daily run.",
		Group = "DailyRewards",
		Args = {},
		Run = function(context)
			local ServerScriptService = game:GetService("ServerScriptService")
			local DailyRewardsService =
				require(ServerScriptService.Features.DailyRewards.DailyRewardsService)
			local Cycle = require(ReplicatedStorage.Features.DailyRewards.Cycle)

			local state = DailyRewardsService.state(context.Executor)
			if state == nil then
				return "Your profile is still loading."
			end
			if state.canClaim then
				return `Day {state.nextDay} of {Constants.CYCLE_DAYS} is open`
					.. ` ({state.claimedThrough} claimed this run).`
			end
			return `Claimed through day {state.claimedThrough}.`
				.. ` Day {state.nextDay} opens in {Cycle.formatDuration(state.secondsUntilReset)}.`
		end,
	},
}
