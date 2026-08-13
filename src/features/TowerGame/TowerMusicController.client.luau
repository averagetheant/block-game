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
-- Gated on the `tower.music` setting (registered in this feature's Settings.luau).
-- The zone still moves the playlist on while music is off, so switching it back
-- on gives you the track for the zone you're actually in rather than resuming
-- one from three checkpoints ago.
--
-- The tracks are Studio-authored and not synced by Rojo; an empty folder just
-- means silence.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)

-- Client-realm siblings (StarterPlayerScripts.Features tree).
local PlayerDataController = require(script.Parent.Parent.PlayerData.PlayerDataController)
local SettingsController = require(script.Parent.Parent.Settings.SettingsController)
local TowerController = require(script.Parent.TowerController)

local TowerMusicController = {}

-- The playing clone, and the catalog Sound it was cloned from. The template
-- outlives the clone: it's what "the current zone's track" means while the
-- music is switched off and there's nothing playing.
local current: Sound? = nil
local currentTemplate: Sound? = nil

-- nil means the toggle isn't registered at all (Settings uninstalled), which is
-- not the player asking for silence — only an explicit false is.
local function allowed(): boolean
	return SettingsController.get(Constants.SETTING_MUSIC) ~= false
end

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

local function stop()
	if current == nil then
		return
	end
	current:Destroy()
	current = nil
end

-- (Re)start whatever template is loaded. A no-op beyond the stop when music is
-- switched off, which is what lets `advance` run the playlist silently.
local function play()
	stop()

	local template = currentTemplate
	if template == nil or not allowed() then
		return
	end

	local sound = template:Clone()
	-- Looped: the track holds the zone rather than handing off partway through
	-- it. The zone change is the only thing that moves the playlist on.
	sound.Looped = true
	sound.Parent = SoundService
	current = sound
	sound:Play()
end

-- Move to the next track, reshuffling when the list runs out.
local function advance()
	if #playlist == 0 or nextIndex > #playlist then
		playlist = shuffled(tracks())
		nextIndex = 1
	end
	local template = playlist[nextIndex]
	if template == nil then
		return
	end
	nextIndex += 1

	currentTemplate = template
	play()
end

-- Toggling music must not burn through the playlist: off destroys the clone and
-- leaves the template loaded, on plays that same template again. Only a zone
-- change advances.
local function applySetting()
	if not allowed() then
		stop()
		return
	end
	if current ~= nil then
		return
	end
	if currentTemplate == nil then
		advance()
		return
	end
	play()
end

function TowerMusicController.Start()
	local lastZoneId: number? = nil

	TowerController.DataChanged:Connect(function(data)
		if data.zoneId == lastZoneId then
			return
		end
		lastZoneId = data.zoneId
		advance()
	end)

	-- Every replica diff, same as the Music feature's controller: SettingsController
	-- reads PlayerData underneath, so flipping the toggle arrives here as a data
	-- change. Redundant fires are harmless — applySetting is idempotent.
	PlayerDataController.DataChanged:Connect(applySetting)

	-- The first state packet may be a while out; don't sit in silence waiting
	-- for it if the folder already has something to play.
	task.delay(2, function()
		if currentTemplate == nil then
			advance()
		end
	end)
end

return TowerMusicController
