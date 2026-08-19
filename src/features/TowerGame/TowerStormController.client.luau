-- The storm arriving, as weather.
--
-- The storm has always been a number on a bar: the stage clock runs out and the
-- tower is taken. This is the minute before that, made audible and visible —
-- ambience fading up out of silence, the sky clouding over, and lightning going
-- off somewhere behind the tower. A player who never looks at the HUD should
-- still feel the last minute coming.
--
-- **Presentation only.** Nothing here touches the clock, the damage or the
-- placement rules; a client that drew none of it plays the identical game. That's
-- also why it all lives on the client: the ramp is derived from `stormEndsAt`,
-- which every client already has, so none of it needs a packet.
--
-- One ramp drives all three, 0 → 1 across `STORM_APPROACH_SECONDS`:
--
--   ambience   volume *is* the ramp, so it cannot be heard before the window
--   clouds     Cover and Density thicken, and the colour goes from white to slate
--   lightning  strikes start sparse and end as a barrage, always behind the tower
--              and always level with the camera, each answered by its own thunder
--
-- The ramp is chased rather than jumped to. Rising it barely matters — the window
-- is a minute wide — but when the storm lands and the next stage's clock starts,
-- the target drops from 1 to 0 on one frame, and a sky that snapped back to clear
-- would undo the whole effect in the moment it was built for.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)
local Sfx = require(ReplicatedStorage.Features.TowerGame.Sfx)

-- Client-realm siblings (StarterPlayerScripts.Features.TowerGame.*).
local LightningBolt = require(script.Parent.LightningBolt)
local PvpController = require(script.Parent.PvpController)
local TowerController = require(script.Parent.TowerController)

local TowerStormController = {}

-- After the camera and the zone visuals; this one only reads state.
TowerStormController.Priority = 30

-- Where the background bolts are parented, so they sweep as a group and never
-- get mistaken for anything in the arena.
local FOLDER_NAME = "TowerStormSky"

local ramp = 0
local nextStrikeAt = 0

local function lerp(from: number, to: number, alpha: number): number
	return from + (to - from) * alpha
end

local function randomInRange(range: { number }): number
	return range[1] + math.random() * (range[2] - range[1])
end

-- How far into the approach the run is, 0 … 1.
--
-- Zero unless a *classic* run is actually live. Three cases would otherwise sit
-- at full storm forever: a PVP match (no storm at all), the round break (the
-- clock has already expired, so "seconds left" is 0, which reads exactly like
-- "the storm is here"), and an idle server.
local function targetRamp(): number
	if PvpController.isActive() then
		return 0
	end

	local data = TowerController.GetData()
	local phase = data.phase
	if phase ~= Constants.PHASE.AIMING and phase ~= Constants.PHASE.SETTLING then
		return 0
	end

	local left = TowerController.stormSecondsLeft()
	if left <= 0 then
		return 0
	end
	return math.clamp((Constants.STORM_APPROACH_SECONDS - left) / Constants.STORM_APPROACH_SECONDS, 0, 1)
end

-- The Volume the Studio Sound was tuned with. Kept because the clone's own Volume
-- is overwritten every frame by the ramp, so it can't be read back off it.
local ambienceBase = 1

-- The looping ambience, cloned from the Studio-authored Sound so it keeps the
-- volume and pitch a human tuned — the clone's Volume is that value scaled by the
-- ramp. Rojo doesn't sync the library, so a place without the cue is simply
-- silent: the sky still darkens and the lightning still strikes.
local function buildAmbience(): Sound?
	local assets = ReplicatedStorage:FindFirstChild(Constants.ASSETS_FOLDER)
	local sounds = if assets then assets:FindFirstChild("Sounds") else nil
	local template = if sounds then sounds:FindFirstChild(Constants.STORM_AMBIENCE_CUE) else nil
	if template == nil or not template:IsA("Sound") then
		warn(
			`[TowerGame] no Sound named "{Constants.STORM_AMBIENCE_CUE}" in Assets.Sounds; `
				.. `the storm arrives silently`
		)
		return nil
	end

	ambienceBase = template.Volume
	local sound = template:Clone()
	sound.Name = "StormAmbience"
	sound.Looped = true
	-- Silent until the ramp says otherwise, and playing the whole time: starting
	-- and stopping it per approach would restart the loop from its first sample
	-- every stage, which is audible on anything with a recognisable opening.
	sound.Volume = 0
	sound.Parent = SoundService
	sound:Play()
	return sound
end

-- The clouds. Created here if the place has none, because this is the only thing
-- that wants them — a place that ships its own gets its own settings ramped
-- instead of a second instance fighting it.
local function buildClouds(): Clouds
	local existing = workspace.Terrain:FindFirstChildOfClass("Clouds")
	if existing then
		return existing
	end
	local clouds = Instance.new("Clouds")
	clouds.Cover = Constants.CLOUD_COVER_CALM
	clouds.Density = Constants.CLOUD_DENSITY_CALM
	clouds.Color = Constants.CLOUD_COLOR_CALM
	clouds.Enabled = true
	clouds.Parent = workspace.Terrain
	return clouds
end

local function skyFolder(): Folder
	local existing = workspace:FindFirstChild(FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = workspace
	return folder
end

-- One strike, somewhere behind the tower.
--
-- Deliberately nowhere near the play plane: these hit nothing and mean nothing,
-- and a bolt that came down *in* the arena would be read as the Stormy zone's
-- hazard — the one that does damage and announces itself with a red column
-- first. Keeping them hundreds of studs back is what keeps the two apart.
--
-- Height is measured from the camera rather than from the world floor, because
-- the camera climbs with the tower: a band pinned to the sky over the base is in
-- shot for the first stage and underfoot for the rest of the run.
local function strikeBackground(parent: Instance, ramp: number)
	local camera = workspace.CurrentCamera
	local eyeY = if camera then camera.CFrame.Position.Y else 0

	local forks = math.random(Constants.BG_LIGHTNING_FORKS[1], Constants.BG_LIGHTNING_FORKS[2])
	local nearest = math.huge

	for _ = 1, forks do
		local x = randomInRange(Constants.BG_LIGHTNING_X)
		local z = randomInRange(Constants.BG_LIGHTNING_Z)
		local from = Vector3.new(x, eyeY + randomInRange(Constants.BG_LIGHTNING_ABOVE), z)
		-- Drifts sideways on the way down, like a real one: a bolt whose ends
		-- share an X is a vertical line however much the middle wanders.
		local to = Vector3.new(
			x + randomInRange({ -140, 140 }),
			eyeY - randomInRange(Constants.BG_LIGHTNING_BELOW),
			z
		)
		LightningBolt.strike({
			from = from,
			to = to,
			width = Constants.BG_LIGHTNING_WIDTH,
			color = Constants.LIGHTNING_BOLT_COLOR,
			parent = parent,
		})

		if camera then
			nearest = math.min(nearest, (to - camera.CFrame.Position).Magnitude)
		end
	end

	if camera == nil or nearest == math.huge then
		return
	end

	-- The clap, once for the whole strike, after the sound has had time to cross
	-- the distance. That delay is the one detail that makes a bolt read as far
	-- away rather than as an effect that fired late.
	local far = math.abs(Constants.BG_LIGHTNING_Z[1])
	local distance = math.clamp(nearest / far, 0, 1)
	local volume = Constants.BG_LIGHTNING_VOLUME
		* ramp
		* (1 - Constants.BG_LIGHTNING_FAR_QUIET * distance)
	task.delay(nearest / Constants.BG_LIGHTNING_SOUND_SPEED, function()
		Sfx.play(Constants.BG_LIGHTNING_CUE, volume)
	end)
end

function TowerStormController.Start()
	local ambience = buildAmbience()
	local clouds = buildClouds()
	local folder = skyFolder()

	RunService.Heartbeat:Connect(function(deltaTime: number)
		local target = targetRamp()
		-- Exponential chase, framerate-independent: the closer `ramp` is to its
		-- target the slower it moves, so it eases in at both ends without a tween
		-- to cancel every time the target changes.
		ramp += (target - ramp) * math.min(deltaTime * Constants.STORM_APPROACH_SMOOTHING, 1)

		if ambience then
			-- Volume *is* the ramp, scaled by what the Sound was tuned to in Studio.
			-- That's what makes "you can't hear it until the last minute" a
			-- property of the thing rather than a rule somebody has to enforce.
			ambience.Volume = ambienceBase * Constants.STORM_AMBIENCE_VOLUME * ramp
		end

		clouds.Cover = lerp(Constants.CLOUD_COVER_CALM, Constants.CLOUD_COVER_STORM, ramp)
		clouds.Density = lerp(Constants.CLOUD_DENSITY_CALM, Constants.CLOUD_DENSITY_STORM, ramp)
		clouds.Color = Constants.CLOUD_COLOR_CALM:Lerp(Constants.CLOUD_COLOR_STORM, ramp)

		-- Below the opening threshold the sky is simply clear: the window has to
		-- start from nothing or there's nothing for it to build out of.
		if ramp < Constants.BG_LIGHTNING_START_RAMP then
			return
		end

		local now = os.clock()
		if now < nextStrikeAt then
			return
		end
		-- The gap interpolates from lonely to constant across the same ramp, so
		-- the first bolts are an event and the last ones are a barrage.
		local gap = {
			lerp(Constants.BG_LIGHTNING_CALM_GAP[1], Constants.BG_LIGHTNING_STORM_GAP[1], ramp),
			lerp(Constants.BG_LIGHTNING_CALM_GAP[2], Constants.BG_LIGHTNING_STORM_GAP[2], ramp),
		}
		nextStrikeAt = now + randomInRange(gap)
		strikeBackground(folder, ramp)
	end)
end

return TowerStormController
