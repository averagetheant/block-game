-- The first-checkpoint quest: the one retention beat this game has.
--
-- Reaching the first checkpoint is where most new players stop playing, so the
-- climb up to it is the only stretch of the game worth paying for directly. The
-- HUD promises a rare skin (see CheckpointQuest.ui) and this is what makes the
-- promise good the moment a checkpoint clears.
--
-- Split out of TowerService deliberately. TowerService is the gameplay
-- authority — arena, turns, physics, storm — and handing out a cosmetic for
-- retention reasons is not that. It's one call at one moment, and keeping it in
-- its own file means the whole feature can be read, retuned or deleted without
-- reading 1800 lines of tower.
--
-- Who qualifies is *not* tracked here: `SeenCheckpoint` on the TowerGame profile
-- slice already means exactly "has this player been in the server for a
-- checkpoint", which is the same question, and a second flag saying the same
-- thing is a second flag to keep in sync.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)

-- Server-realm siblings (ServerScriptService.Features.*).
local TowerStatsService = require(script.Parent.TowerStatsService)
-- Ownership of a pack is Store's to write — `grantPack` is the one blessed way
-- a pack arrives, whether it was bought, claimed from the daily run, or earned
-- here, so this never reaches into the profile itself.
local StoreService = require(script.Parent.Parent.Store.StoreService)

local CheckpointQuestService = {}

-- A checkpoint just cleared. Hands the prize to everyone in the server who
-- hasn't seen one before, then closes the quest for all of them.
--
-- Everyone present, not just whoever placed the last piece: it's one shared
-- tower, so clearing a floor is one shared moment — the same rule `recordHeight`
-- and the zone payout already follow.
--
-- **The grant happens before the flag write.** `isFirstCheckpointFor` reads the
-- flag `recordCheckpointSeen` sets, so doing it the other way round would close
-- the quest on every player a line before paying them.
function CheckpointQuestService.award()
	for _, player in Players:GetPlayers() do
		if not TowerStatsService.isFirstCheckpointFor(player) then
			continue
		end
		-- Already owning it counts as granted, so a player who somehow has the
		-- pack already still gets their quest closed rather than being asked to
		-- clear another checkpoint for a skin they own.
		StoreService.grantPack(player, Constants.FIRST_CHECKPOINT_PACK)
	end

	TowerStatsService.recordCheckpointSeen()
end

return CheckpointQuestService
