--!strict
-- Discovery + realm-correct registration for feature commands.
--
-- Why this exists: Cmdr validates the name you type against the **client's**
-- registry, and normally fills that registry by *replicating a definition
-- ModuleScript* — `Registry:RegisterCommand` reparents the script into
-- `Cmdr.ReplicatedRoot.Commands`, and clients register what shows up there. A
-- server-only `RegisterCommandObject` call never reaches the client, so the
-- console answers "not a valid command name" for a command the server has
-- registered perfectly well. That's silent: nothing warns, and the command works
-- fine if you call it from server code.
--
-- Scripts can't be authored at runtime, so we can't hand Cmdr a module to
-- replicate. Instead the *definition* lives in a shared module both realms read,
-- and each realm registers it itself:
--
--   * server — the whole definition, `Run` included; it executes the command.
--   * client — the definition with `Run` stripped, so Cmdr accepts the name and
--     dispatches to the server. `Command:Run` runs locally when the object has a
--     `Run` and falls through to the server when it doesn't, which is exactly
--     the behaviour a server command wants.
--
-- A feature adds commands by dropping a sibling `Commands.luau` returning a list
-- of Cmdr command definitions — the same auto-discovery convention as
-- `PlayerData.luau` / `Settings.luau` / `Gamemode.luau`, so the Cmdr feature
-- names nobody. A feature that gates commands behind its own
-- `Presentations.command` flag returns an empty list when it's off.
--
-- `Run` is only ever *called* on the server, so a definition's `Run` body may
-- require server-realm modules — but lazily, inside the function. Never at the
-- top level of `Commands.luau`, which both realms load.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CommandRegistry = {}

-- Everything Cmdr accepts on a command object. Anything else makes
-- RegisterCommandObject throw, so we check here and name the feature instead of
-- letting Cmdr raise from inside the loop.
local ALLOWED_KEYS = {
	Name = true,
	Aliases = true,
	AutoExec = true,
	Description = true,
	Args = true,
	Run = true,
	ClientRun = true,
	Data = true,
	Group = true,
}

-- The client copy keeps everything but `Run`. `ClientRun` deliberately survives:
-- a command that genuinely runs locally is still allowed to.
local function withoutRun(definition: any): any
	local copy = table.clone(definition)
	copy.Run = nil
	return copy
end

local function definitionsFrom(mod: ModuleScript): { any }?
	local ok, result = pcall(require, mod)
	if not ok then
		warn(`[Cmdr] failed to require {mod:GetFullName()}: {result}`)
		return nil
	end
	if typeof(result) ~= "table" then
		warn(`[Cmdr] {mod:GetFullName()} must return a list of command definitions; got {typeof(result)}`)
		return nil
	end
	return result
end

-- Register every feature's commands into `cmdr` — the server Cmdr on the server,
-- CmdrClient on the client. Safe to call once per realm; a second call would
-- just overwrite the same names.
function CommandRegistry.registerAll(cmdr: any)
	local isServer = RunService:IsServer()
	local features = ReplicatedStorage:FindFirstChild("Features")
	if features == nil then
		return
	end

	for _, featureModule in features:GetChildren() do
		local mod = featureModule:FindFirstChild("Commands")
		if mod == nil or not mod:IsA("ModuleScript") then
			continue
		end

		local definitions = definitionsFrom(mod)
		if definitions == nil then
			continue
		end

		for _, definition in definitions do
			if typeof(definition) ~= "table" or typeof(definition.Name) ~= "string" then
				warn(`[Cmdr] {mod:GetFullName()} contains an entry with no Name; skipped`)
				continue
			end
			for key in definition do
				if ALLOWED_KEYS[key] == nil then
					warn(`[Cmdr] command "{definition.Name}" in {mod:GetFullName()} has unknown key "{key}"`)
				end
			end

			local object = if isServer then definition else withoutRun(definition)
			local ok, err = pcall(function()
				cmdr.Registry:RegisterCommandObject(object)
			end)
			if not ok then
				warn(`[Cmdr] failed to register "{definition.Name}" from {mod:GetFullName()}: {err}`)
			end
		end
	end
end

return CommandRegistry
