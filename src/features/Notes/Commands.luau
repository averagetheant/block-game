-- Command presentation for Notes (seam #4: a Cmdr command instead of a screen
-- GUI). `setnote <text>` routes to the SAME server-side core intent the GUI
-- packet routes to — NotesService.setNote — so both surfaces write through one
-- validated path.
--
-- Shared module, discovered by the Cmdr feature on BOTH realms: the server
-- registers this with `Run`, the client registers it without so the console
-- accepts the name. See src/features/Cmdr/CommandRegistry.luau for why. The
-- server-realm require lives inside Run, which only executes on the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Features.Notes.Constants)

if not Constants.Presentations.command then
	return {}
end

return {
	{
		Name = "setnote",
		Aliases = {},
		Description = "Set your saved note (Notes feature).",
		Group = "Notes",
		Args = {
			{
				Type = "string",
				Name = "text",
				Description = "The note text to save (clamped server-side).",
			},
		},
		Run = function(context, text: string)
			local ServerScriptService = game:GetService("ServerScriptService")
			local NotesService = require(ServerScriptService.Features.Notes.NotesService)
			NotesService.setNote(context.Executor, text)
			return `Note saved: {text}`
		end,
	},
}
