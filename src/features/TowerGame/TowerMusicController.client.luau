-- Background music: cycles the tracks in `ReplicatedStorage.Assets.Music`.
--
-- Shuffled rather than sequential, and reshuffled each time the list is
-- exhausted, so a long session doesn't feel like a loop. Client-side, one Sound
-- at a time, parented to SoundService — each player drives their own playlist,
-- which is the right call for background music (a server-driven track would make
-- everyone share one clock for no benefit).
--
-- The tracks are Studio-authored and not synced by Rojo; an empty folder just
-- means silence.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)

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

function TowerMusicController.Start()
	task.spawn(function()
		while true do
			local playlist = shuffled(tracks())
			if #playlist == 0 then
				-- Nothing authored yet: check back rather than spinning.
				task.wait(10)
				continue
			end

			for _, template in playlist do
				local sound = template:Clone()
				sound.Looped = false
				sound.Parent = SoundService
				current = sound
				sound:Play()

				-- Ended doesn't fire for a track that fails to load, so cap the
				-- wait at the track's own length with a little slack.
				local finished = false
				sound.Ended:Once(function()
					finished = true
				end)
				local deadline = os.clock() + math.max(sound.TimeLength, 1) + 5
				repeat
					task.wait(0.5)
				until finished or os.clock() > deadline

				sound:Destroy()
				current = nil
			end
		end
	end)
end

return TowerMusicController
