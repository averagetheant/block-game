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
local Sfx = require(ReplicatedStorage.Features.TowerGame.Sfx)
local Zones = require(ReplicatedStorage.Features.TowerGame.Zones)

-- Client-realm sibling (StarterPlayerScripts.Features.TowerGame.TowerController).
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
		if zone.warning then
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
	local height = TowerController.GetData().height
	local arena = workspace:FindFirstChild(Constants.ARENA_NAME)
	local baseTop = if arena then arena:GetAttribute(Constants.BASE_TOP_ATTRIBUTE) else nil
	part.Position = Vector3.new(0, (baseTop or 0) + height + Constants.WEATHER_HEIGHT, Constants.PLANE_Z)
end

-- Draw a bolt onto the point the server said was struck. Purely local: a beam
-- from high above down onto the block, gone almost immediately — the explosion
-- and the sound are what carry the event, this just gives the eye somewhere to
-- land first.
local function drawBolt(at: Vector3)
	local bolt = Instance.new("Part")
	bolt.Name = BOLT_NAME
	bolt.Anchored = true
	bolt.CanCollide = false
	bolt.CanQuery = false
	bolt.CanTouch = false
	bolt.CastShadow = false
	bolt.Material = Enum.Material.Neon
	bolt.Color = Constants.LIGHTNING_BOLT_COLOR
	bolt.Size = Vector3.new(
		Constants.LIGHTNING_BOLT_WIDTH,
		Constants.LIGHTNING_BOLT_HEIGHT,
		Constants.LIGHTNING_BOLT_WIDTH
	)
	-- Sits *on* the struck point with its whole length above, so the bolt reads
	-- as coming down out of the sky rather than skewering the block.
	bolt.Position = at + Vector3.new(0, Constants.LIGHTNING_BOLT_HEIGHT / 2, 0)
	bolt.Parent = workspace

	local light = Instance.new("PointLight")
	light.Range = 60
	light.Brightness = 6
	light.Color = Constants.LIGHTNING_BOLT_COLOR
	light.Parent = bolt

	TweenService:Create(
		bolt,
		TweenInfo.new(Constants.LIGHTNING_BOLT_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Transparency = 1 }
	):Play()
	game:GetService("Debris"):AddItem(bolt, Constants.LIGHTNING_BOLT_SECONDS + 0.1)
end

-- The red column standing on the spot the next bolt will hit. Pulses so it reads
-- as a countdown rather than as scenery, and is removed the moment the server
-- clears the attribute — which it does immediately before the strike lands.
local warning: BasePart? = nil

local function clearWarning()
	if warning then
		warning:Destroy()
		warning = nil
	end
end

local function showWarning(at: Vector3)
	clearWarning()

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
	-- The server sends the *base* of the column, so the marker stands on the
	-- bottom plate and runs all the way up through everything built in it —
	-- which is what makes it read as "this whole line is about to be hit"
	-- rather than as a mark floating at one height.
	part.Position = at + Vector3.new(0, Constants.WARN_HEIGHT / 2, 0)
	part.Parent = workspace
	warning = part
end

function TowerZoneController.Start()
	local lastZoneId, lastSky = nil, nil

	TowerController.DataChanged:Connect(function(data)
		if data.zoneId == lastZoneId and data.zoneSky == lastSky then
			return
		end
		lastZoneId, lastSky = data.zoneId, data.zoneSky
		applyZone(data.zoneId, data.zoneSky)
	end)

	-- The arena carries the strike position as an attribute. Waiting for the
	-- arena rather than assuming it exists: the client can boot before the server
	-- has built it.
	task.spawn(function()
		local arena = workspace:WaitForChild(Constants.ARENA_NAME)

		arena:GetAttributeChangedSignal(Constants.STRIKE_ATTRIBUTE):Connect(function()
			local at = arena:GetAttribute(Constants.STRIKE_ATTRIBUTE)
			if typeof(at) == "Vector3" then
				drawBolt(at)
			end
		end)

		-- nil is the server saying "no bolt pending", which happens both when one
		-- lands and when the zone changes out from under a warning.
		arena:GetAttributeChangedSignal(Constants.WARN_ATTRIBUTE):Connect(function()
			local at = arena:GetAttribute(Constants.WARN_ATTRIBUTE)
			if typeof(at) == "Vector3" then
				showWarning(at)
			else
				clearWarning()
			end
		end)

		-- A player who joins mid-warning gets it too; attributes are already set
		-- by the time they replicate in, so there's no change event to wait for.
		local existing = arena:GetAttribute(Constants.WARN_ATTRIBUTE)
		if typeof(existing) == "Vector3" then
			showWarning(existing)
		end

		-- The pulse. Driven here rather than by a tween so it survives the marker
		-- being replaced, and costs one property write a frame.
		RunService.RenderStepped:Connect(function()
			local part = warning
			if part == nil then
				return
			end
			local wave = (math.sin(os.clock() * Constants.WARN_PULSE_HZ * math.pi * 2) + 1) / 2
			part.Transparency = Constants.WARN_TRANSPARENCY - wave * 0.18
		end)
	end)

	task.spawn(function()
		while true do
			task.wait(0.5)
			followTower()
			-- Blocks arrive constantly, so a zone-change sweep alone would leave
			-- everything placed *during* the night unlit.
			if appliedZoneId ~= nil and Zones.get(appliedZoneId).kind == "night" then
				applyBlockLights(Zones.get(appliedZoneId))
			end
		end
	end)
end

return TowerZoneController
