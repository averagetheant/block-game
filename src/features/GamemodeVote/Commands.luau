-- Command presentation for GamemodeVote (seam #4).
--
-- `startvote` opens a poll on demand, routed through the same core intent
-- TowerGame's checkpoint calls — GamemodeVoteService.startVote — so the command
-- tests the real thing rather than a parallel path.
--
-- Note it has no *consumer*: the winner comes back to the console and nothing
-- applies it. To see a vote actually change how a stage plays, use TowerGame's
-- `skipstage`, which runs the checkpoint that feeds the result into the stage.
--
-- Shared module, discovered by the Cmdr feature on BOTH realms: the server
-- registers this with `Run`, the client registers it without so the console
-- accepts the name. See src/features/Cmdr/CommandRegistry.luau for why. The
-- server-realm require lives inside Run, which only executes on the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Features.GamemodeVote.Constants)

if not Constants.Presentations.command then
	return {}
end

return {
	{
		Name = "startvote",
		Aliases = {},
		Description = "Open a gamemode vote now (GamemodeVote feature).",
		Group = "GamemodeVote",
		Args = {},
		Run = function()
			local ServerScriptService = game:GetService("ServerScriptService")
			local GamemodeVoteService =
				require(ServerScriptService.Features.GamemodeVote.GamemodeVoteService)

			if GamemodeVoteService.isActive() then
				return "A vote is already open."
			end
			-- startVote yields for the length of the poll, and Cmdr shows the
			-- return value when it comes back — so the console reports the winner.
			local winner = GamemodeVoteService.startVote()
			if winner == nil then
				return "No gamemodes are registered; nothing to vote on."
			end
			return `Vote won by "{winner}".`
		end,
	},
}
