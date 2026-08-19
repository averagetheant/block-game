-- TowerGame's one-shot sound effects, cloned from the Studio-authored library at
-- `ReplicatedStorage.Assets.Sounds`.
--
-- The loading, cloning and cleanup all live in the framework now
-- (`Boil.audio.playCue*`) — this is the feature's thin binding to it, and exists
-- for one reason: every TowerGame cue carries the same falloff
-- (`Constants.SOUND_RANGE`), and threading that through a dozen call sites would
-- be repeating a decision that belongs in one place.
--
-- Cloning rather than referencing an asset id is the framework's rule and the
-- reason this indirection is worth having: the Sound instances in that folder
-- carry the volume and pitch they were tuned with, so re-tuning a cue is a
-- Studio edit and not a code change. Rojo doesn't sync that folder, so a missing
-- sound warns once and is otherwise a no-op — audio going quiet should never
-- take gameplay down with it.
--
-- Realm-neutral. On the client, `play` is local to that player; the server has
-- `playAt` / `playAtPosition` for world sounds everyone should hear.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local audio = require(ReplicatedStorage.Shared.Boil).audio
local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)

local Sfx = {}

-- Warm this client's asset cache with the whole cue library, impact takes and
-- all. **Yields** — see `audio.preloadCues`; `TowerFeedbackController` spawns it
-- at start.
function Sfx.preload()
	audio.preloadCues()
end

-- Fire and forget, heard only where it's called (2D on the client).
function Sfx.play(name: string, volumeScale: number?)
	audio.playCue(name, { volumeScale = volumeScale })
end

-- Positional one-shot parented to a part, so it carries to every client with
-- distance falloff. Server-side use.
function Sfx.playAt(name: string, part: BasePart, volumeScale: number?)
	audio.playCueAt(name, part, {
		volumeScale = volumeScale,
		rollOffMaxDistance = Constants.SOUND_RANGE,
	})
end

-- Positional one-shot that outlives whatever caused it — a blast still sounds
-- from where it happened even though the block that exploded is already gone.
function Sfx.playAtPosition(name: string, position: Vector3, volumeScale: number?)
	audio.playCueAtPosition(name, position, {
		volumeScale = volumeScale,
		rollOffMaxDistance = Constants.SOUND_RANGE,
	})
end

return Sfx
