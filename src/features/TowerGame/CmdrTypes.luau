-- Cmdr argument types for TowerGame's commands (seam #4 support).
--
-- Auto-discovered by src/features/Cmdr/CommandRegistry.luau, the same
-- convention as Commands.luau: a feature drops a sibling `CmdrTypes.luau`
-- returning a list of `{ Name, Values }` pairs, and CommandRegistry turns each
-- into a validated, autocompleted Cmdr enum type (via `Cmdr.Util.MakeEnumType`)
-- on both realms — the client needs it too, since that's what drives the
-- console's autocomplete dropdown. Named `CmdrTypes` rather than `Types` on
-- purpose: `Types.luau` is already a convention for pure Luau type exports
-- (see PickupFX/Types.luau, UIShell/Types.luau) — reusing that name here would
-- collide with it.
--
-- Shared module: safe to require BlockTypes/BlockSkins/Zones at the top level
-- since they're all shared data modules already loaded on both realms.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)

if not Constants.Presentations.command then
	return {}
end

local BlockSkins = require(ReplicatedStorage.Features.TowerGame.BlockSkins)
local BlockTypes = require(ReplicatedStorage.Features.TowerGame.BlockTypes)
local Zones = require(ReplicatedStorage.Features.TowerGame.Zones)

-- "Normal" isn't a BlockTypes entry — it's the "block" command's way of
-- saying "no hazard", i.e. blockType = nil at spawn.
local blockTypeNames = { "Normal" }
for _, blockType in BlockTypes.List do
	table.insert(blockTypeNames, blockType.name)
end

local blockSkinNames = {}
for _, skin in BlockSkins.List do
	table.insert(blockSkinNames, skin.name)
end

local zoneNames = {}
for _, zone in Zones.List do
	table.insert(zoneNames, zone.name)
end

return {
	{ Name = "blockType", Values = blockTypeNames },
	{ Name = "blockSkin", Values = blockSkinNames },
	{ Name = "zoneName", Values = zoneNames },
}
