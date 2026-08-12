-- Background music: one track per zone, from `ReplicatedStorage.Assets.Music`.
--
-- The track changes when the *zone* does, not when the track ends — a zone is
-- the game's chapter, so it's the thing worth scoring. Within a zone the track
-- loops rather than moving on, which is why a run through a long zone stays on
-- one piece of music instead of shuffling under the player every minute.
--
-- Shuffled and reshuffled once the list is exhausted, so a long session doesn't
-- repeat in a fixed order. Client-side, one Sound at a time — each player drives
-- their own playlist, which is the right call for background music.
--
-- The tracks are Studio-authored and not synced by Rojo; an empty folder just
-- means silence.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)

-- Client-realm sibling (StarterPlayerScripts.Features.TowerGame.TowerController).
local TowerController = require(script.Parent.TowerController)

local TowerMusicController = {}

local current: Sound? = nil

local function tracks(): { Sound }
	local assets = ReplicatedStorage:FindFirstChild(Constants.ASSETS_FOLDER)
	local folder = if assets then assets:FindFirstChild("Music") else nil
	if folder == nil then
		return {}
	end

	local list = {}
	for _, child in folder:GetChildren() do
		if child:IsA("Sound") then
			table.insert(list, child)
		end
	end
	return list
end

local function shuffled(list: { Sound }): { Sound }
	local copy = table.clone(list)
	for index = #copy, 2, -1 do
		local swap = math.random(1, index)
		copy[index], copy[swap] = copy[swap], copy[index]
	end
	return copy
end

local playlist: { Sound } = {}
local nextIndex = 1

-- Advance to the next track, reshuffling when the list runs out.
local function playNext()
	if #playlist == 0 or nextIndex > #playlist then
		playlist = shuffled(tracks())
		nextIndex = 1
	end
	local template = playlist[nextIndex]
	if template == nil then
		return
	end
	nextIndex += 1

	if current then
		current:Destroy()
	end

	local sound = template:Clone()
	-- Looped: the track holds the zone rather than handing off partway through
	-- it. The zone change is the only thing that moves the playlist on.
	sound.Looped = true
	sound.Parent = SoundService
	current = sound
	sound:Play()
end

function TowerMusicController.Start()
	local lastZoneId: number? = nil

	TowerController.DataChanged:Connect(function(data)
		if data.zoneId == lastZoneId then
			return
		end
		lastZoneId = data.zoneId
		playNext()
	end)

	-- The first state packet may be a while out; don't sit in silence waiting
	-- for it if the folder already has something to play.
	task.delay(2, function()
		if current == nil then
			playNext()
		end
	end)
end

return TowerMusicController
