-- Command presentation for TowerGame (seam #4).
--
-- `skipstage` clears the current storm stage from wherever the tower is, routed
-- through the same core intent the height poll calls when the target is genuinely
-- reached — TowerService.clearStage — so it exercises the real checkpoint
-- sequence rather than a parallel path. Worth having because everything that
-- happens between stages (the cutscene, the blast, the zone roll, the gamemode
-- vote) is otherwise a 60-stud climb away.
--
-- Shared module, discovered by the Cmdr feature on BOTH realms: the server
-- registers this with `Run`, the client registers it without so the console
-- accepts the name. See src/features/Cmdr/CommandRegistry.luau for why.
--
-- Because the client loads this file too, the server-realm require lives *inside*
-- Run — which only ever executes on the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)

if not Constants.Presentations.command then
	return {}
end

return {
	{
		Name = "skipstage",
		Aliases = { "skiplevel" },
		Description = "Clear the current storm stage now (runs the full checkpoint, vote included).",
		Group = "TowerGame",
		Args = {},
		Run = function()
			local ServerScriptService = game:GetService("ServerScriptService")
			local TowerService = require(ServerScriptService.Features.TowerGame.TowerService)
			if not TowerService.clearStage() then
				return "A checkpoint is already running."
			end
			-- Deliberately doesn't wait for the sequence: the cutscene runs for
			-- seconds and the vote for longer, and a console that sat there
			-- blocking on it would look hung.
			return "Stage cleared — checkpoint running."
		end,
	},
}
