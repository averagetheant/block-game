-- Command presentation for TowerGame (seam #4).
--
-- `skipstage` and `skip` both clear the current storm stage, routed through the
-- same core intent the "Next Checkpoint" Robux purchase calls —
-- TowerService.clearStage — so they exercise the real checkpoint sequence
-- (cutscene, platform, blast, zone roll) rather than a parallel path, and jump
-- the tower to the target height exactly like the paid prompt does. Worth
-- having because everything that happens between stages is otherwise a climb
-- away. `skip` exists as its own name so it reads as "replicate the Skip
-- purchase" rather than a dev-only alias.
--
-- `block` pins the next piece's type and/or skin for testing either in
-- isolation. `zone` forces the tower straight into a zone. `givecash` credits
-- Tower Cash directly, the same path CashService pays out through.
--
-- Shared module, discovered by the Cmdr feature on BOTH realms: the server
-- registers this with `Run`, the client registers it without so the console
-- accepts the name. See src/features/Cmdr/CommandRegistry.luau for why.
--
-- Because the client loads this file too, the server-realm require lives *inside*
-- Run — which only ever executes on the server. BlockTypes/BlockSkins/Zones are
-- shared data modules, so those are required at the top level like normal.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)

if not Constants.Presentations.command then
	return {}
end

local BlockSkins = require(ReplicatedStorage.Features.TowerGame.BlockSkins)
local BlockTypes = require(ReplicatedStorage.Features.TowerGame.BlockTypes)
local Gamemodes = require(ReplicatedStorage.Features.TowerGame.Gamemodes)
local Zones = require(ReplicatedStorage.Features.TowerGame.Zones)

local function findBlockType(name: string): BlockTypes.BlockType?
	for _, blockType in BlockTypes.List do
		if blockType.name:lower() == name:lower() then
			return blockType
		end
	end
	return nil
end

local function findBlockSkin(name: string): BlockSkins.Skin?
	for _, skin in BlockSkins.List do
		if skin.name:lower() == name:lower() then
			return skin
		end
	end
	return nil
end

local function findZone(name: string): Zones.Zone?
	for _, zone in Zones.List do
		if zone.name:lower() == name:lower() then
			return zone
		end
	end
	return nil
end

local function clearStage(): string
	local ServerScriptService = game:GetService("ServerScriptService")
	local TowerService = require(ServerScriptService.Features.TowerGame.TowerService)
	if not TowerService.clearStage() then
		return "A checkpoint is already running."
	end
	-- Deliberately doesn't wait for the sequence: the cutscene runs for seconds
	-- and the vote for longer, and a console that sat there blocking on it
	-- would look hung.
	return "Stage cleared — checkpoint running."
end

-- The Extend Storm purchase, without the purchase. Same core intent the receipt
-- handler calls, so it exercises the real thing rather than a parallel path —
-- and it's the only way to check the product works without spending Robux,
-- since the effect is a number on a clock nobody can see from outside.
local function extendStorm(seconds: number): string
	local ServerScriptService = game:GetService("ServerScriptService")
	local TowerService = require(ServerScriptService.Features.TowerGame.TowerService)
	if not TowerService.extendStorm(seconds) then
		return "Can't extend right now — a checkpoint or round break is running."
	end
	return `Storm pushed back {seconds}s.`
end

return {
	{
		Name = "extendstorm",
		Aliases = { "extend" },
		Description = "Replicate the Extend Storm purchase: put seconds back on the stage clock.",
		Group = "TowerGame",
		Args = {
			{
				Type = "number",
				Name = "seconds",
				Description = "How long to push the storm back. Defaults to the product's own amount.",
				Default = Constants.EXTEND_STORM_SECONDS,
			},
		},
		Run = function(_context, seconds: number)
			return extendStorm(seconds)
		end,
	},
	{
		Name = "skipstage",
		Aliases = { "skiplevel" },
		Description = "Clear the current storm stage now (runs the full checkpoint, vote included).",
		Group = "TowerGame",
		Args = {},
		Run = function()
			return clearStage()
		end,
	},
	{
		Name = "skip",
		Aliases = {},
		Description = "Replicate the Skip / Next Checkpoint purchase: jump the tower to the next checkpoint.",
		Group = "TowerGame",
		Args = {},
		Run = function()
			return clearStage()
		end,
	},
	{
		Name = "block",
		Aliases = {},
		Description = "Pin the next piece's block type and/or skin (type default: normal, skin default: random).",
		Group = "TowerGame",
		Args = {
			{
				Type = "blockType",
				Name = "blocktype",
				Description = "Block type to force. Default: Normal.",
				Optional = true,
			},
			{
				Type = "blockSkin",
				Name = "blockskin",
				Description = "Skin to force. Default: random.",
				Optional = true,
			},
		},
		Run = function(context, blocktype: string?, blockskin: string?)
			local ServerScriptService = game:GetService("ServerScriptService")
			local TowerService = require(ServerScriptService.Features.TowerGame.TowerService)

			local resolvedType = if blocktype and blocktype:lower() ~= "normal" then findBlockType(blocktype) else nil
			local resolvedSkin = if blockskin then findBlockSkin(blockskin) else nil

			TowerService.forceNextBlock(resolvedType, resolvedSkin)
			return `Next piece forced: {if resolvedType then resolvedType.name else "Normal"} / {if resolvedSkin
				then resolvedSkin.name
				else "Random"}`
		end,
	},
	{
		Name = "blockrate",
		Aliases = { "specials" },
		Description = "Hold the odds a piece is special at a flat rate. No argument puts the curve back.",
		Group = "TowerGame",
		Args = {
			{
				Type = "number",
				Name = "chance",
				Description = "0 to 1. Omit to hand the roll back to the checkpoint curve.",
				Optional = true,
			},
		},
		Run = function(_context, chance: number?)
			local ServerScriptService = game:GetService("ServerScriptService")
			local TowerService = require(ServerScriptService.Features.TowerGame.TowerService)

			if chance == nil then
				TowerService.setBlockTypeChance(nil)
				return "Special-block odds back on the curve."
			end

			local clamped = math.clamp(chance, 0, 1)
			TowerService.setBlockTypeChance(clamped)
			return `Special-block odds held at {math.floor(clamped * 100)}%.`
		end,
	},
	{
		Name = "gamemode",
		Aliases = { "pvp" },
		Description = "End the round now and play the given gamemode next, skipping the vote.",
		Group = "TowerGame",
		Args = {
			{
				Type = "string",
				Name = "mode",
				Description = "Gamemode id from Gamemodes.luau. Defaults to pvp.",
				Default = "pvp",
			},
		},
		Run = function(_context, mode: string)
			local ServerScriptService = game:GetService("ServerScriptService")
			local TowerService = require(ServerScriptService.Features.TowerGame.TowerService)

			local id = mode:lower()
			local known = false
			for _, entry in Gamemodes.List do
				if entry.id:lower() == id then
					id = entry.id
					known = true
					break
				end
			end
			if not known then
				return `Unknown gamemode "{mode}".`
			end

			-- Routed through the real round break, so this is the round the vote
			-- would have produced rather than a parallel path — which is the whole
			-- point of having it.
			if not TowerService.forceRound(id) then
				return "Can't switch right now — a checkpoint or round break is running."
			end
			-- Deliberately doesn't wait: the wreck, the fade and the break run for
			-- several seconds, and a console blocking on them would look hung.
			return `Round ending — {id} next.`
		end,
	},
	{
		Name = "zone",
		Aliases = {},
		Description = "Force the tower's current zone.",
		Group = "TowerGame",
		Args = {
			{
				Type = "zoneName",
				Name = "zone",
				Description = "Zone to switch to.",
			},
		},
		Run = function(context, zoneName: string)
			local ServerScriptService = game:GetService("ServerScriptService")
			local TowerService = require(ServerScriptService.Features.TowerGame.TowerService)

			local zone = findZone(zoneName)
			if zone == nil then
				return `Unknown zone "{zoneName}".`
			end
			TowerService.setZone(zone.id)
			return `Zone set to {zone.name}.`
		end,
	},
	{
		Name = "givecash",
		Aliases = {},
		Description = "Give a player Tower Cash.",
		Group = "TowerGame",
		Args = {
			{
				Type = "player",
				Name = "player",
				Description = "Who to pay.",
			},
			{
				Type = "positiveInteger",
				Name = "amount",
				Description = "How much cash to give.",
			},
		},
		Run = function(context, player: Player, amount: number)
			local ServerScriptService = game:GetService("ServerScriptService")
			local CashService = require(ServerScriptService.Features.TowerGame.CashService)
			-- Tagged so a dev topping themselves up in a live place is visibly
			-- separate from the earn curve on the economy dashboard.
			CashService.award(player, amount, "Admin")
			return `Gave {player.Name} {amount} cash.`
		end,
	},
}
