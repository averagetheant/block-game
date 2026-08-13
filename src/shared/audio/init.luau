--!strict
-- Centralized sound/music registry plus thin playback helpers.
--
-- Two sources of sound, and which you want depends on who authored it:
--
--   * **The registry** (`Audio.UI` / `Audio.Music`) — rbxassetids written in
--     this file. Client-side, 2D, no Studio setup. Reach for this for anything
--     stable enough to be part of the kit.
--
--   * **The cue library** (`playCue*`) — Sounds a *human* built and tuned in
--     Studio, under `ReplicatedStorage.Assets.Sounds`. The instance carries its
--     own Volume and PlaybackSpeed, so re-tuning a cue is a Studio edit rather
--     than a code change, and the same call works from either realm. Rojo
--     doesn't sync that folder, so a missing cue warns once and is otherwise a
--     no-op — audio going quiet should never take gameplay down with it.
--
-- Usage:
--   local audio = require(ReplicatedStorage.Shared.audio)
--
--   audio.playUI("click")             -- fire-and-forget one-shot SFX
--   audio.playUI("levelUp", 0.7)      -- override volume
--   audio.playMusic("lobby")          -- swap looping background track
--   audio.playMusic("phonk", 0.4)     -- override volume
--   audio.stopMusic()                 -- stop background music
--   audio.currentTrack()              -- nil | the active music Sound
--   audio.playCue("Stamp")            -- Studio-authored one-shot, heard locally
--   audio.playCueAt("Drop", part)     -- …positionally, from the server
--
-- The registry half is **client-side**: UI sounds use
-- `SoundService:PlayLocalSound`, which is local-only by design and errors on the
-- server. Music is played by parenting a single looping Sound to SoundService on
-- the client, so each player drives their own track independently. `playCueAt` /
-- `playCueAtPosition` are the exception — they parent a real Sound into the
-- world, so a server call is heard by everyone, which is exactly what a world
-- event wants.
--
-- Note: Roblox does not play audio inside Studio plugins (UI Labs runs as a
-- plugin), so the Audio story's playback buttons are silent in-edit. Audition
-- the registry by Play-testing the game, not from UI Labs.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Audio = {}

-- Short one-shot UI SFX. Keys are referenced as strings by `playUI`.
Audio.UI = {
	click = "rbxassetid://6895079853",
	click2 = "rbxassetid://103866342467024",
	purchase = "rbxassetid://134952684776633",
	equip = "rbxassetid://70430710356859",
	hoverIn = "rbxassetid://99955064134003",
	hoverOut = "rbxassetid://10066931761",
	levelUp = "rbxassetid://112485797063762",
	swipe = "rbxassetid://10128766965",
	select = "rbxassetid://10128760939",
	reward = "rbxassetid://82616454607059",
	tick = "rbxassetid://9055474333",
	money = "rbxassetid://307631257",
}

-- Looping music tracks. Keys are referenced as strings by `playMusic`.
Audio.Music = {
	fastMusic = "rbxassetid://140228184971194",
	phonk = "rbxassetid://138118304933431",
	phonk2 = "rbxassetid://140675348569592",
	xmas = "rbxassetid://140633727133993",
	lobby = "rbxassetid://1841647742",
	lobby2 = "rbxassetid://114376757380093",
	lobby3 = "rbxassetid://1840684529",
}

export type UISoundKey =
	"click" | "click2" | "purchase" | "equip" | "hoverIn" | "hoverOut" | "levelUp"
	| "swipe" | "select" | "reward" | "tick" | "money"

export type MusicKey =
	"fastMusic" | "phonk" | "phonk2" | "xmas" | "lobby" | "lobby2" | "lobby3"

local DEFAULT_UI_VOLUME = 1
local DEFAULT_MUSIC_VOLUME = 0.2

-- One-shot UI sound. Plays via SoundService (no 3D position). PlayLocalSound
-- doesn't yield and is safe from event handlers.
function Audio.playUI(name: string, volume: number?)
	local id = Audio.UI[name]
	if not id then
		warn(`[audio] unknown UI sound "{name}"`)
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or DEFAULT_UI_VOLUME
	s.Ended:Connect(function()
		s:Destroy()
	end)
	SoundService:PlayLocalSound(s)
	-- Safety net for assets that never fire Ended (bad encoder, etc.).
	task.delay(15, function()
		if s.Parent ~= nil or s.IsPlaying then
			s:Destroy()
		end
	end)
end

-- Play an arbitrary one-shot by rbxassetid. Use this for sounds outside the
-- registry (e.g. user-uploaded picks, asset-id from data). Prefer `playUI` for
-- anything that's stable enough to live in the registry.
function Audio.playSoundId(id: string, volume: number?)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or DEFAULT_UI_VOLUME
	s.Ended:Connect(function()
		s:Destroy()
	end)
	SoundService:PlayLocalSound(s)
	task.delay(15, function()
		if s.Parent ~= nil or s.IsPlaying then
			s:Destroy()
		end
	end)
end

local currentMusic: Sound? = nil
local currentMusicKey: string? = nil

-- Swap looping background music. If the requested track is already playing,
-- this is a no-op (returns the existing Sound). Otherwise destroys the prior
-- Sound and starts the new one. Returns the active Sound so callers can fade
-- Volume, hook .Ended, etc.
function Audio.playMusic(name: string, volume: number?): Sound?
	local id = Audio.Music[name]
	if not id then
		warn(`[audio] unknown music track "{name}"`)
		return nil
	end
	if currentMusic and currentMusicKey == name then
		return currentMusic
	end
	if currentMusic then
		currentMusic:Destroy()
		currentMusic = nil
		currentMusicKey = nil
	end
	local s = Instance.new("Sound")
	s.Name = `Music_{name}`
	s.SoundId = id
	s.Volume = volume or DEFAULT_MUSIC_VOLUME
	s.Looped = true
	s.Parent = SoundService
	s:Play()
	currentMusic = s
	currentMusicKey = name
	return s
end

function Audio.stopMusic()
	if currentMusic then
		currentMusic:Destroy()
		currentMusic = nil
		currentMusicKey = nil
	end
end

function Audio.currentTrack(): Sound?
	return currentMusic
end

function Audio.currentTrackName(): string?
	return currentMusicKey
end

------------------------------------------------------------------------------
-- The cue library (Studio-authored one-shots)
------------------------------------------------------------------------------

-- Where the cue library lives, as a path under ReplicatedStorage. Fields rather
-- than constants so a project laid out differently can repoint them at boot
-- without forking this file; the framework names no feature either way.
Audio.CUE_FOLDER = "Assets"
Audio.CUE_SUBFOLDER = "Sounds"

-- How far a positional cue carries, and how it falls off. Overridable per call
-- for a cue that should reach further than the rest.
Audio.DEFAULT_CUE_RANGE = 200
Audio.DEFAULT_CUE_ROLLOFF = Enum.RollOffMode.InverseTapered

-- How long a cue is given to finish before it's cleaned up regardless. `Ended`
-- is the normal path; this is the net for an asset that never loads and so never
-- fires it.
local CUE_LIFETIME = 15

export type CueOptions = {
	-- Multiplies the Volume the Sound was tuned with in Studio, rather than
	-- replacing it — the whole point of the library is that a human set that.
	volumeScale: number?,
	rollOffMaxDistance: number?,
	rollOffMode: Enum.RollOffMode?,
}

local warnedCues: { [string]: boolean } = {}

local function cueLibrary(): Folder?
	local root = ReplicatedStorage:FindFirstChild(Audio.CUE_FOLDER)
	if root == nil then
		return nil
	end
	local sounds = root:FindFirstChild(Audio.CUE_SUBFOLDER)
	return if sounds and sounds:IsA("Folder") then sounds else nil
end

-- The template for `name`, or nil with a one-time warning. Once per name, not
-- once per call: a cue fired every frame would otherwise fill the output.
local function cueTemplate(name: string): Sound?
	local library = cueLibrary()
	local sound = if library then library:FindFirstChild(name) else nil
	if sound == nil or not sound:IsA("Sound") then
		if not warnedCues[name] then
			warnedCues[name] = true
			warn(`[audio] missing cue "{name}" under {Audio.CUE_FOLDER}.{Audio.CUE_SUBFOLDER}`)
		end
		return nil
	end
	return sound
end

local function cleanUp(sound: Sound, holder: Instance?)
	local function destroy()
		if holder then
			holder:Destroy()
		else
			sound:Destroy()
		end
	end
	sound.Ended:Once(destroy)
	task.delay(CUE_LIFETIME, destroy)
end

local function prepareCue(name: string, options: CueOptions?): Sound?
	local source = cueTemplate(name)
	if source == nil then
		return nil
	end
	local opts = options or {}

	local sound = source:Clone()
	sound.Volume = source.Volume * (opts.volumeScale or 1)
	return sound
end

-- Fire and forget, heard only where it's called (2D, client-side).
function Audio.playCue(name: string, options: CueOptions?)
	local sound = prepareCue(name, options)
	if sound == nil then
		return
	end
	sound.Parent = SoundService
	sound:Play()
	cleanUp(sound)
end

-- Positional one-shot parented to a part, so it carries to every client with
-- distance falloff. Server-side use — the Sound replicates with the part.
function Audio.playCueAt(name: string, part: BasePart, options: CueOptions?)
	if part.Parent == nil then
		return
	end
	local sound = prepareCue(name, options)
	if sound == nil then
		return
	end
	local opts = options or {}
	sound.RollOffMaxDistance = opts.rollOffMaxDistance or Audio.DEFAULT_CUE_RANGE
	sound.RollOffMode = opts.rollOffMode or Audio.DEFAULT_CUE_ROLLOFF
	sound.Parent = part
	sound:Play()
	cleanUp(sound)
end

-- Positional one-shot that outlives whatever caused it. Parents the Sound to a
-- throwaway anchored marker, so a blast still sounds from where it happened even
-- though the thing that exploded is already gone.
function Audio.playCueAtPosition(name: string, position: Vector3, options: CueOptions?)
	local sound = prepareCue(name, options)
	if sound == nil then
		return
	end
	local opts = options or {}

	local marker = Instance.new("Part")
	marker.Name = "AudioCueMarker"
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.Transparency = 1
	marker.Size = Vector3.one
	marker.Position = position
	marker.Parent = workspace

	sound.RollOffMaxDistance = opts.rollOffMaxDistance or Audio.DEFAULT_CUE_RANGE
	sound.RollOffMode = opts.rollOffMode or Audio.DEFAULT_CUE_ROLLOFF
	sound.Parent = marker
	sound:Play()
	cleanUp(sound, marker)
end

return Audio
