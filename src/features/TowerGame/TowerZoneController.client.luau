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

local appliedZoneId: number? = nil
local weather: BasePart? = nil

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

local function applyZone(zoneId: number, roll: number)
	local zone = Zones.get(zoneId)
	applySky(zone, roll)
	applyWeather(zone)

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

function TowerZoneController.Start()
	local lastZoneId, lastSky = nil, nil

	TowerController.DataChanged:Connect(function(data)
		if data.zoneId == lastZoneId and data.zoneSky == lastSky then
			return
		end
		lastZoneId, lastSky = data.zoneId, data.zoneSky
		applyZone(data.zoneId, data.zoneSky)
	end)

	task.spawn(function()
		while true do
			task.wait(0.5)
			followTower()
		end
	end)
end

return TowerZoneController
