-- One-shot sound effects, cloned from the Studio-authored library at
-- `ReplicatedStorage.Assets.Sounds`.
--
-- Cloning rather than referencing an asset id on purpose: the Sound instances in
-- that folder carry the volume and pitch they were tuned with, so re-tuning a
-- cue is a Studio edit and not a code change. Rojo doesn't sync that folder, so
-- a missing sound warns once and is otherwise a no-op — audio going quiet should
-- never take gameplay down with it.
--
-- Realm-neutral. On the client, `play` is local to that player; the server has
-- `playAt` for world sounds everyone should hear.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)

local Sfx = {}

local warned: { [string]: boolean } = {}

local function library(): Folder?
	local assets = ReplicatedStorage:FindFirstChild(Constants.ASSETS_FOLDER)
	return if assets then assets:FindFirstChild("Sounds") :: Folder else nil
end

local function template(name: string): Sound?
	local sounds = library()
	local sound = if sounds then sounds:FindFirstChild(name) else nil
	if sound == nil or not sound:IsA("Sound") then
		if not warned[name] then
			warned[name] = true
			warn(`[TowerGame] missing sound "{name}" under Assets.Sounds`)
		end
		return nil
	end
	return sound
end

-- Fire and forget, heard only where it's called (2D on the client).
function Sfx.play(name: string, volumeScale: number?)
	local source = template(name)
	if source == nil then
		return
	end

	local sound = source:Clone()
	sound.Volume = source.Volume * (volumeScale or 1)
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	-- Safety net: a sound that never loads never fires Ended.
	task.delay(15, function()
		sound:Destroy()
	end)
end

-- Positional one-shot parented to a part, so it carries to every client with
-- distance falloff. Server-side use.
function Sfx.playAt(name: string, part: BasePart, volumeScale: number?)
	local source = template(name)
	if source == nil or part.Parent == nil then
		return
	end

	local sound = source:Clone()
	sound.Volume = source.Volume * (volumeScale or 1)
	sound.RollOffMaxDistance = Constants.SOUND_RANGE
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.Parent = part
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(15, function()
		sound:Destroy()
	end)
end

return Sfx
