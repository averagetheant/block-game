-- Hands the Duck skin to the two people it belongs to, and to nobody else.
--
-- Duck is the one cosmetic in the game with no route in: it isn't rolled
-- (`weight = 0` in BlockSkins), it isn't sold (`forSale = false` in SkinPacks),
-- and no quest or daily reward names it. This file is the entire supply.
--
-- Split out of CheckpointQuestService rather than added to it for the reason
-- that file gives for existing at all: a grant made for one reason shouldn't
-- have to be read past to understand a grant made for another. This one has
-- nothing to do with retention — it's a personal skin for two named accounts,
-- and it should be as easy to delete as it was to add.
--
-- **Ownership is not re-checked after the grant.** Taking a name off
-- Constants.DUCK_OWNERS stops it being handed out; it doesn't take it back off a
-- profile that already has it. Revoking a cosmetic someone has equipped is a
-- different decision from not granting one, and it isn't this file's to make.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)

-- `grantPack` is the one blessed way a pack arrives however it was earned, so
-- this never reaches into the profile itself — the rule CheckpointQuestService
-- follows for the gold skin.
local PlayerDataService = require(ServerScriptService.Features.PlayerData.PlayerDataService)
local StoreService = require(ServerScriptService.Features.Store.StoreService)

local DuckSkinService = {}

-- After PlayerData (1) and Store, so `grantPack` and the catalog are both ready
-- by the time the first player is looked at. The same band FavouritePrompt sits
-- in, and for the same reason: nothing waits on this one.
DuckSkinService.Priority = 10

-- How long to wait for a profile before giving up on a join, in seconds. The
-- grant needs somewhere to write, and a profile that hasn't loaded is not that.
-- Matches the window Analytics gives its own arrival count.
local PROFILE_TIMEOUT = 60

-- Lowercased once at load. Roblox usernames are unique case-insensitively, so
-- comparing this way is strictly safer than an exact match and can't collide.
local owners: { [string]: boolean } = {}
for _, name in Constants.DUCK_OWNERS do
	owners[string.lower(name)] = true
end

local function isOwner(player: Player): boolean
	return owners[string.lower(player.Name)] == true
end

-- Wait for the profile, then hand it over. Polled rather than driven off a
-- signal because PlayerData doesn't publish one — the same shape Analytics uses
-- to hold its onboarding step until there's something to write to.
local function grant(player: Player)
	for _ = 1, PROFILE_TIMEOUT do
		if player.Parent == nil then
			return
		end
		if PlayerDataService.GetData(player) ~= nil then
			-- Already owning it counts as success, so a rejoin is a no-op rather
			-- than a second write.
			StoreService.grantPack(player, Constants.DUCK_PACK)
			return
		end
		task.wait(1)
	end
	warn(`[Duck] {player.Name}'s profile never loaded; they did not get the duck skin this session`)
end

local function onPlayerAdded(player: Player)
	if not isOwner(player) then
		return
	end
	task.spawn(grant, player)
end

function DuckSkinService.Start()
	-- Anyone already in when this starts, then everyone after. Studio's own
	-- player is in the server before services run, and without the first loop
	-- they'd have to rejoin to see it.
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
end

return DuckSkinService
