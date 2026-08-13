--!strict
-- Registers TowerGame's gamemodes into the GamemodeVote feature.
--
-- Discovered by GamemodeVote's auto-discovery loop, which requires this file and
-- calls it with its own public table — so nothing here requires GamemodeVote and
-- there's no cycle. Same convention as the sibling `PlayerData.luau` /
-- `Settings.luau` files.
--
-- Delete GamemodeVote and this file becomes inert; delete TowerGame and the
-- ballot is simply empty. Neither feature's source mentions the other's content.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Gamemodes = require(ReplicatedStorage.Features.TowerGame.Gamemodes)

return function(GamemodeVote: any)
	for _, mode in Gamemodes.List do
		GamemodeVote.register(mode)
	end
end
