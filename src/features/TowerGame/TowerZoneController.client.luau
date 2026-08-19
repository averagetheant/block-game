-- The visual half of a zone: sky, weather, and the cue that one arrived.
--
-- The server decides *which* zone (it owns the physics half — slippery blocks,
-- wind, retro studs) and broadcasts the id. Every client paints it from the same
-- id, so nobody has to trust their own roll.
--
-- Every asset here is Studio-authored under `ReplicatedStorage.Assets` and is
-- NOT synced by Rojo. Each lookup degrades to "leave it as it was" rather than
-- erroring — a missing skybox should cost you a nice sky, not the game.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Signal = require(ReplicatedStorage.Packages.Signal)

local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)
local PvpConstants = require(ReplicatedStorage.Features.TowerGame.PvpConstants)
local PvpLanes = require(ReplicatedStorage.Features.TowerGame.PvpLanes)
local Sfx = require(ReplicatedStorage.Features.TowerGame.Sfx)
local Zones = require(ReplicatedStorage.Features.TowerGame.Zones)

-- Client-realm siblings (StarterPlayerScripts.Features.TowerGame.*). The zone is
-- announced on whichever mode's packet is live, so both stores are read here.
local LightningBolt = require(script.Parent.LightningBolt)
local PvpController = require(script.Parent.PvpController)
local TowerController = require(script.Parent.TowerController)

local TowerZoneController = {}

-- Fires with a Zones.Zone whenever a *special* zone starts, for the HUD banner.
TowerZoneController.ZoneWarned = Signal.new()

local SKY_NAME = "TowerZoneSky"
local WEATHER_NAME = "TowerZoneWeather"
-- Name every block light shares, so clearing them is one sweep for a name rather
-- than bookkeeping a list that a destroyed block would leave stale entries in.
local BLOCK_LIGHT_NAME = "TowerNightLight"
local BOLT_NAME = "TowerLightningBolt"

local appliedZoneId: number? = nil
local weather: BasePart? = nil

-- What Lighting looked like before a zone touched it. Captured once, on the
-- first change, so restoring is "put back what the place file had" rather than a
-- second set of hardcoded numbers that could drift from it.
local baseLighting: { brightness: number, ambient: Color3, clockTime: number, fogStart: number, fogEnd: number, fogColor: Color3 }? =
	nil

local function rememberLighting()
	if baseLighting ~= nil then
		return
	end
	baseLighting = {
		brightness = Lighting.Brightness,
		ambient = Lighting.Ambient,
		clockTime = Lighting.ClockTime,
		fogStart = Lighting.FogStart,
		fogEnd = Lighting.FogEnd,
		fogColor = Lighting.FogColor,
	}
end

local function assets(): Folder?
	return ReplicatedStorage:FindFirstChild(Constants.ASSETS_FOLDER) :: Folder?
end

local function zoneFolder(): Folder?
	local root = assets()
	return if root then root:FindFirstChild("Zones") :: Folder else nil
end

-- Normal zones roll one of the skies in Assets.Zones.Normal. The server sends an
-- arbitrary number rather than an index, because it has no idea how many skies
-- exist — that's a Studio asset it can't see. Modulo here is what turns that
-- into a pick, so adding a sky in Studio needs no server change.
local function skyFor(zone: Zones.Zone, roll: number): Sky?
	local folder = zoneFolder()
	if folder == nil then
		return nil
	end

	if zone.sky then
		local named = folder:FindFirstChild(zone.sky)
		return if named and named:IsA("Sky") then named else nil
	end

	local normal = folder:FindFirstChild("Normal")
	if normal == nil then
		return nil
	end
	local options = {}
	for _, child in normal:GetChildren() do
		if child:IsA("Sky") then
			table.insert(options, child)
		end
	end
	if #options == 0 then
		return nil
	end
	return options[(roll % #options) + 1]
end

local function applySky(zone: Zones.Zone, roll: number)
	local template = skyFor(zone, roll)
	if template == nil then
		return
	end

	local existing = Lighting:FindFirstChild(SKY_NAME)
	if existing then
		existing:Destroy()
	end
	local sky = template:Clone()
	sky.Name = SKY_NAME
	sky.Parent = Lighting
end

-- Weather is a Studio-built part full of emitters. It rides above the tower so
-- the particles fall *through* the play area rather than starting inside it.
local function applyWeather(zone: Zones.Zone)
	if weather then
		weather:Destroy()
		weather = nil
	end

	local root = assets()
	if root == nil then
		return
	end

	local templateName = if zone.kind == "snowy"
		then "SnowParticle"
		elseif zone.kind == "stormy" then "RainParticle"
		else nil
	if templateName == nil then
		return
	end

	local template = root:FindFirstChild(templateName)
	if template == nil or not template:IsA("BasePart") then
		return
	end

	local part = template:Clone()
	part.Name = WEATHER_NAME
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Parent = workspace
	weather = part
end

-- Fog and darkness. Both are Lighting properties, so both are purely local — the
-- server never touches Lighting, and a client that fails here just sees the
-- plain world.
local function applyLighting(zone: Zones.Zone)
	rememberLighting()
	local base = baseLighting :: any

	if zone.kind == "foggy" then
		Lighting.FogStart = Constants.FOG_START
		Lighting.FogEnd = Constants.FOG_END
		Lighting.FogColor = Constants.FOG_COLOR
	else
		Lighting.FogStart = base.fogStart
		Lighting.FogEnd = base.fogEnd
		Lighting.FogColor = base.fogColor
	end

	if zone.kind == "night" then
		Lighting.Brightness = Constants.NIGHT_BRIGHTNESS
		Lighting.Ambient = Constants.NIGHT_AMBIENT
		Lighting.ClockTime = Constants.NIGHT_CLOCK_TIME
	else
		Lighting.Brightness = base.brightness
		Lighting.Ambient = base.ambient
		Lighting.ClockTime = base.clockTime
	end
end

-- Night gives every block its own light, so the tower lights itself and the
-- players build by what they've already placed.
--
-- One light per *block*, hung on the model's first part rather than on every
-- cell: four lights on a tetromino costs four times as much and looks the same.
-- Client-side, so it's decoration the server never has to know about.
local function applyBlockLights(zone: Zones.Zone)
	local arena = workspace:FindFirstChild(Constants.ARENA_NAME)
	if arena == nil then
		return
	end
	local wantLights = zone.kind == "night"

	for _, model in arena:GetChildren() do
		if not model:IsA("Model") then
			continue
		end
		local part = model:FindFirstChildWhichIsA("BasePart")
		if part == nil then
			continue
		end

		local existing = part:FindFirstChild(BLOCK_LIGHT_NAME)
		if not wantLights then
			if existing then
				existing:Destroy()
			end
			continue
		end
		if existing then
			continue
		end

		local light = Instance.new("PointLight")
		light.Name = BLOCK_LIGHT_NAME
		light.Range = Constants.NIGHT_LIGHT_RANGE
		light.Brightness = Constants.NIGHT_LIGHT_BRIGHTNESS
		-- Takes the block's own colour, so a tower of mixed skins lights the
		-- arena in the colours the players actually built with.
		light.Color = part.Color
		light.Parent = part
	end
end

local function applyZone(zoneId: number, roll: number)
	local zone = Zones.get(zoneId)
	applySky(zone, roll)
	applyWeather(zone)
	applyLighting(zone)
	applyBlockLights(zone)

	-- The first zone of a session is the world booting up, not an event.
	if appliedZoneId ~= nil then
		Sfx.play("ZoneReached")
		-- Only a zone that bends a rule announces itself. Asked of the zone rather
		-- than of its copy: every zone carries a line now (the PVP reel prints one
		-- whatever it lands on), and "clear skies" is not a banner.
		if Zones.announces(zone) then
			TowerZoneController.ZoneWarned:Fire(zone)
		end
	end
	appliedZoneId = zoneId
end

-- Keep the weather riding above whatever has been built, so it never ends up
-- raining below the tower's top.
local function followTower()
	local part = weather
	if part == nil then
		return
	end
	-- In PVP the weather follows the player's *own* lane, since that's what their
	-- camera is on. Snow falling over the middle of a six-lane board would be
	-- weather nobody is standing in.
	local x = 0
	local height = TowerController.GetData().height
	local mine = PvpController.myLane()
	if mine ~= nil then
		x = PvpLanes.xOf(mine.slot)
		height = mine.height
	end
	local arena = workspace:FindFirstChild(Constants.ARENA_NAME)
	local baseTop = if arena then arena:GetAttribute(Constants.BASE_TOP_ATTRIBUTE) else nil
	part.Position = Vector3.new(x, (baseTop or 0) + height + Constants.WEATHER_HEIGHT, Constants.PLANE_Z)
end

-- Draw a bolt onto the point the server said was struck. Purely local: a beam
-- from high above down onto the block, gone almost immediately — the explosion
-- and the sound are what carry the event, this just gives the eye somewhere to
-- land first.
local function drawBolt(at: Vector3)
	-- Ends *on* the struck point with its whole run above, so the bolt reads as
	-- coming down out of the sky rather than skewering the block.
	--
	-- Through the same renderer the storm's background strikes use, so the
	-- lightning that costs you a tower and the lightning that's only weather are
	-- the same object at different distances. It used to be a single straight
	-- Neon box, which read as a beam next to a branching one.
	--
	-- Fewer passes than the background bolts get: this one is a few studs from
	-- the camera rather than half a world away, and at that range four passes of
	-- displacement is a scribble instead of a fork.
	LightningBolt.strike({
		from = at + Vector3.new(0, Constants.LIGHTNING_BOLT_HEIGHT, 0),
		to = at,
		width = Constants.LIGHTNING_BOLT_WIDTH,
		color = Constants.LIGHTNING_BOLT_COLOR,
		parent = workspace,
		passes = Constants.LIGHTNING_BOLT_PASSES,
		fadeSeconds = Constants.LIGHTNING_BOLT_SECONDS,
	})

	-- The flash the bolt throws on the tower, on a part of its own: the bolt is
	-- now a few dozen segments rather than one, and hanging a light on whichever
	-- of them happened to be first would put it at a random height up the strike.
	local flash = Instance.new("Part")
	flash.Name = BOLT_NAME
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CanTouch = false
	flash.CastShadow = false
	flash.Transparency = 1
	flash.Size = Vector3.one
	flash.Position = at + Vector3.new(0, Constants.LIGHTNING_BOLT_HEIGHT / 2, 0)
	flash.Parent = workspace

	local light = Instance.new("PointLight")
	light.Range = 60
	light.Brightness = 6
	light.Color = Constants.LIGHTNING_BOLT_COLOR
	light.Parent = flash

	TweenService:Create(
		light,
		TweenInfo.new(Constants.LIGHTNING_BOLT_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Brightness = 0 }
	):Play()
	game:GetService("Debris"):AddItem(flash, Constants.LIGHTNING_BOLT_SECONDS + 0.1)
end

-- The blue columns standing where the next bolts will hit. Each pulses so it
-- reads as a countdown rather than as scenery, and each is removed the moment the
-- server clears its attribute — which it does immediately before the strike lands.
--
-- Keyed by the instance that announced it, because a PVP match can have six up at
-- once. A classic run has exactly one announcer (the arena); a match announces
-- each lane's bolt on that lane's own platform, which is also the floor its column
-- stands on. `x` is kept beside the part so the column can be re-seated as the
-- floor under it moves without asking the server again.
type Marker = { part: BasePart, x: number }
local markers: { [Instance]: Marker } = {}

-- The altitude a column stands on, asked of whoever announced it.
--
-- A **lane platform** is the floor its lane builds from, and it's a part the
-- client can measure — which is the whole reason PVP announces bolts on the
-- platform rather than on the arena. It can't use the classic answer below: the
-- classic packet is frozen for the length of a match, so `zoneBaseHeight` would be
-- whatever the last classic round left there.
--
-- The **arena** means the classic run, where it's the floor the run is currently
-- building from — the checkpoint platform it last cleared. Standing the column on
-- the arena's base instead is what made the warning vanish a few stages in: the
-- base ends up hundreds of studs below the play area, and a 400-stud column down
-- there is entirely out of frame. `zoneBaseHeight` is the same number the camera
-- frames its shots from, so the marker is guaranteed to sit inside the shot rather
-- than near it.
local function floorFor(source: Instance): number
	if source:IsA("BasePart") then
		return source.Position.Y + source.Size.Y / 2
	end
	local baseTop = source:GetAttribute(Constants.BASE_TOP_ATTRIBUTE)
	return (if typeof(baseTop) == "number" then baseTop else 0)
		+ math.max(TowerController.GetData().zoneBaseHeight, 0)
end

local function clearWarning(source: Instance)
	local marker = markers[source]
	if marker == nil then
		return
	end
	marker.part:Destroy()
	markers[source] = nil
end

local function showWarning(source: Instance, x: number)
	clearWarning(source)

	local part = Instance.new("Part")
	part.Name = "TowerLightningWarning"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = Constants.WARN_COLOR
	part.Transparency = Constants.WARN_TRANSPARENCY
	part.Size = Vector3.new(Constants.WARN_WIDTH, Constants.WARN_HEIGHT, Constants.WARN_WIDTH)
	-- Stood on the floor rather than centred on a point, so the marker runs all
	-- the way up through everything built in that column — which is what makes it
	-- read as "this whole line is about to be hit" rather than as a mark floating
	-- at one height.
	part.Position = Vector3.new(x, floorFor(source) + Constants.WARN_HEIGHT / 2, Constants.PLANE_Z)
	part.Parent = workspace
	markers[source] = { part = part, x = x }
end

-- The floor only moves when a checkpoint lands, which can happen while a warning
-- is already standing. Polled with the weather rather than driven per frame:
-- without it the column spends the rest of its ten seconds under the new floor.
--
-- A source that has gone (a PVP lane retired mid-warning, or the whole match
-- ending) takes its column with it: the server can't clear an attribute on a part
-- it has already destroyed.
local function followFloor()
	for source, marker in markers do
		if source.Parent == nil then
			clearWarning(source)
			continue
		end
		marker.part.Position =
			Vector3.new(marker.x, floorFor(source) + Constants.WARN_HEIGHT / 2, Constants.PLANE_Z)
	end
end

function TowerZoneController.Start()
	local lastZoneId, lastSky = nil, nil
	-- Bumped by every announcement, so a paint waiting out a roll window can tell
	-- whether it's still the one that's owed.
	local pendingZone = 0

	-- Both modes carry the zone on their own packet, and the classic one stops
	-- being sent for the length of a PVP match — so the zone is read from
	-- whichever packet arrived, through one handler that doesn't care which. The
	-- dedupe below is what makes that safe: two sources agreeing on the same zone
	-- re-apply nothing.
	--
	-- `at` is the server time the zone becomes true. In PVP it sits up to
	-- `ZONE_ROLL_SECONDS` ahead of the packet that announced it, and the whole
	-- visual half waits for it: the HUD spends that window spinning a reel through
	-- the zone names (see `ZoneReel`), and a sky that changed while the reel was
	-- still turning would give the answer away and land the world's change on a
	-- different beat from the HUD's. The classic packet has no such window and
	-- passes a time already gone, which paints immediately.
	local function onZone(zoneId: number, sky: number, at: number)
		if zoneId == lastZoneId and sky == lastSky then
			return
		end
		lastZoneId, lastSky = zoneId, sky
		pendingZone += 1
		local token = pendingZone

		-- Capped at the window the server is allowed to ask for: a stamp that
		-- arrived wrong (a clock that hasn't synced yet, a packet from a build
		-- that means something else by it) should land the zone early, never
		-- leave the world painted for the zone before it.
		local wait = math.min(at - workspace:GetServerTimeNow(), PvpConstants.ZONE_ROLL_SECONDS)
		if wait <= 0 then
			applyZone(zoneId, sky)
			return
		end

		task.delay(wait, function()
			-- A newer announcement, or the match ending, retires this one.
			if token ~= pendingZone then
				return
			end
			applyZone(zoneId, sky)
		end)
	end

	TowerController.DataChanged:Connect(function(data)
		-- A stale classic packet arriving mid-match must not drag the world back
		-- to the zone the last round ended in.
		if PvpController.isActive() then
			return
		end
		onZone(data.zoneId, data.zoneSky, 0)
	end)

	PvpController.DataChanged:Connect(function(data)
		if data.phase == PvpConstants.PHASE.OFF then
			-- The match can end mid-roll. The server retires its own pending apply
			-- at the same moment (see `rollZone`), so a reel that never landed must
			-- not leave the sky painted for a zone the world never took. Forgetting
			-- what's up as well as cancelling is what lets the next classic packet
			-- put its own zone back even if it names the one just announced.
			pendingZone += 1
			lastZoneId, lastSky = nil, nil
			return
		end
		onZone(data.zoneId, data.zoneSky, data.zoneAt)
	end)

	-- Bolts and their warnings are read off attributes on whoever announced them:
	-- the arena for a classic run, and each lane's own platform for a PVP match,
	-- where six can be in the air at once. One watcher covers both — it never asks
	-- which mode is running, only which instance spoke.
	local function watchSource(source: Instance)
		source:GetAttributeChangedSignal(Constants.STRIKE_ATTRIBUTE):Connect(function()
			local at = source:GetAttribute(Constants.STRIKE_ATTRIBUTE)
			if typeof(at) == "Vector3" then
				drawBolt(at)
			end
		end)

		-- nil is the server saying "no bolt pending", which happens when one
		-- lands, when the zone changes out from under a warning, and when a match
		-- ends mid-warning.
		source:GetAttributeChangedSignal(Constants.WARN_ATTRIBUTE):Connect(function()
			local x = source:GetAttribute(Constants.WARN_ATTRIBUTE)
			if typeof(x) == "number" then
				showWarning(source, x)
			else
				clearWarning(source)
			end
		end)

		-- A player who joins mid-warning gets it too; attributes are already set
		-- by the time they replicate in, so there's no change event to wait for.
		-- Same for a lane platform, which replicates with its attribute already on
		-- it if it was built during a warning.
		local existing = source:GetAttribute(Constants.WARN_ATTRIBUTE)
		if typeof(existing) == "number" then
			showWarning(source, existing)
		end
	end

	-- Waiting for the arena rather than assuming it exists: the client can boot
	-- before the server has built it.
	task.spawn(function()
		local arena = workspace:WaitForChild(Constants.ARENA_NAME)
		watchSource(arena)

		-- The lanes folder comes and goes with each match, and its platforms come
		-- and go with the players in them, so both are watched rather than read
		-- once. A retired lane's column is cleaned up by `followFloor`, which
		-- notices the platform has left the world.
		local function watchLanes(folder: Instance)
			for _, child in folder:GetChildren() do
				if child:IsA("BasePart") then
					watchSource(child)
				end
			end
			folder.ChildAdded:Connect(function(child)
				if child:IsA("BasePart") then
					watchSource(child)
				end
			end)
		end

		local existingLanes = arena:FindFirstChild(PvpConstants.LANES_FOLDER)
		if existingLanes then
			watchLanes(existingLanes)
		end
		arena.ChildAdded:Connect(function(child)
			if child.Name == PvpConstants.LANES_FOLDER then
				watchLanes(child)
			end
		end)

		-- The pulse. Driven here rather than by a tween so it survives a marker
		-- being replaced, and costs one property write per marker per frame.
		RunService.RenderStepped:Connect(function()
			if next(markers) == nil then
				return
			end
			local wave = (math.sin(os.clock() * Constants.WARN_PULSE_HZ * math.pi * 2) + 1) / 2
			local transparency = Constants.WARN_TRANSPARENCY - wave * 0.18
			for _, marker in markers do
				marker.part.Transparency = transparency
			end
		end)
	end)

	task.spawn(function()
		while true do
			task.wait(0.5)
			followTower()
			followFloor()
			-- Blocks arrive constantly, so a zone-change sweep alone would leave
			-- everything placed *during* the night unlit.
			if appliedZoneId ~= nil and Zones.get(appliedZoneId).kind == "night" then
				applyBlockLights(Zones.get(appliedZoneId))
			end
		end
	end)
end

return TowerZoneController
