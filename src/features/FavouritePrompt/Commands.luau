-- Command presentation for FavouritePrompt (seam #4: a Cmdr command instead of a
-- screen GUI — the prompt itself is Roblox's, so there's nothing to open).
--
-- `favouriteprompt` clears the once-ever flag on the executor, so the next
-- gamemode vote asks again. It's the only way to see this flow twice: it's
-- keyed to the account, and you don't get a fresh account per test run. Pair it
-- with GamemodeVote's `startvote` to go straight to the ask.
--
-- Shared module, discovered by the Cmdr feature on BOTH realms: the server
-- registers this with `Run`, the client registers it without so the console
-- accepts the name. See src/features/Cmdr/CommandRegistry.luau for why. The
-- server-realm require lives inside Run, which only executes on the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Features.FavouritePrompt.Constants)

if not Constants.Presentations.command then
	return {}
end

return {
	{
		Name = "favouriteprompt",
		Aliases = { "favoriteprompt" },
		Description = "Clear the once-ever favourite prompt so the next vote asks again.",
		Group = "FavouritePrompt",
		Args = {},
		Run = function(context)
			local ServerScriptService = game:GetService("ServerScriptService")
			local FavouritePromptService =
				require(ServerScriptService.Features.FavouritePrompt.FavouritePromptService)

			if not FavouritePromptService.reset(context.Executor) then
				return "Your profile is still loading."
			end
			-- The client's session guard is cleared by the replica diff landing,
			-- not by this returning — see the controller.
			return "Cleared. The next gamemode vote will ask you to favourite."
		end,
	},
}
