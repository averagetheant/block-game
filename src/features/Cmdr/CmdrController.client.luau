local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CommandRegistry = require(ReplicatedStorage.Features.Cmdr.CommandRegistry)
local Constants = require(ReplicatedStorage.Features.Cmdr.Constants)

local CmdrController = {}

function CmdrController.Start()
	-- CmdrClient is inserted into ReplicatedStorage by the server Cmdr bootstrap,
	-- so we must WaitForChild rather than require it statically.
	local CmdrClient = require(ReplicatedStorage:WaitForChild("CmdrClient"))
	CmdrClient:SetActivationKeys(Constants.ActivationKeys)

	-- Custom argument types before the commands that reference them by name —
	-- this is also what makes the console autocomplete their values.
	CommandRegistry.registerTypes(CmdrClient)

	-- The console checks what you type against *this* registry, so a feature
	-- command that only ever registered on the server reads as "not a valid
	-- command name". Registering the same definitions here (minus Run) is what
	-- makes them typeable; they still execute on the server.
	CommandRegistry.registerAll(CmdrClient)
end

return CmdrController
