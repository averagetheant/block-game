-- Camera presentation for TowerGame: a fixed, level shot of the play plane that
-- rides the tower's altitude and nothing else. No orbit, no follow-the-avatar —
-- the only thing that ever changes is Y and, for one moment per stage, how far
-- back it stands.
--
-- It reads height straight off TowerController's store rather than taking a prop,
-- which is what lets it be deleted (Presentations.camera = false) without any
-- other file noticing. The same goes for the checkpoint pull-back: the server
-- sends no camera cue, it just says PHASE.CHECKPOINT, and this file decides what
-- that looks like.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)
local PvpConstants = require(ReplicatedStorage.Features.TowerGame.PvpConstants)
local PvpLanes = require(ReplicatedStorage.Features.TowerGame.PvpLanes)

-- Client-realm siblings (StarterPlayerScripts.Features.TowerGame.*).
local TowerController = require(script.Parent.TowerController)
local PvpController = require(script.Parent.PvpController)

local TowerCameraController = {}

local RENDER_NAME = "TowerGameCamera"

-- The player's own pull-back, toggled from the HUD's camera button.
--
-- Deliberately *not* honoured during the checkpoint cutscene or the round break:
-- those own the camera for their duration and frame something specific, and a
-- player who happened to leave overview on would otherwise miss the shot the
-- game is trying to show them. `target` checks phase first for exactly that
-- reason — the toggle is a preference, not an override.
local overview = false

function TowerCameraController.toggleOverview(): boolean
	overview = not overview
	return overview
end

function TowerCameraController.isOverview(): boolean
	return overview
end

-- The altitude every shot is measured from. The server publishes it as an
-- attribute once the arena exists, which may be after the client boots.
local function waitForBaseTop(): number
	local arena = workspace:WaitForChild(Constants.ARENA_NAME)
	local top = arena:GetAttribute(Constants.BASE_TOP_ATTRIBUTE)
	while top == nil do
		arena:GetAttributeChangedSignal(Constants.BASE_TOP_ATTRIBUTE):Wait()
		top = arena:GetAttribute(Constants.BASE_TOP_ATTRIBUTE)
	end
	return top :: number
end

function TowerCameraController.Start()
	if not Constants.Presentations.camera then
		return
	end

	-- Phone framing is its own shot. A phone held upright has far less vertical
	-- room than a monitor, so the desktop lift put the tower top near the middle
	-- of the screen and everything the player had built ran off the bottom —
	-- which reads as the camera sitting too high. Aim lower, stand further back.
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local aimLift = if touchOnly then Constants.CAMERA_AIM_LIFT_TOUCH else Constants.CAMERA_AIM_LIFT
	local distance = if touchOnly then Constants.CAMERA_DISTANCE_TOUCH else Constants.CAMERA_DISTANCE

	local halfAngle = math.rad(Constants.CAMERA_FOV) / 2
	-- Half the height the ordinary shot has in frame, at its ordinary distance.
	local halfSpan = distance * math.tan(halfAngle)

	-- `aimX` is which column of the arena the camera stands in front of. Zero for
	-- every classic shot — one tower, at the origin — and the player's own lane
	-- in PVP, which is the whole of "your camera follows your tower".
	local function shot(aimX: number, aimY: number, from: number): CFrame
		return CFrame.lookAt(
			Vector3.new(aimX, aimY, Constants.PLANE_Z + from),
			Vector3.new(aimX, aimY, Constants.PLANE_Z)
		)
	end

	-- How far back `span` studs of height need the camera to stand — and never
	-- closer than the *width* of the play area needs it to be.
	--
	-- Roblox's FieldOfView is vertical, so the height in frame is the same on
	-- every device and the width is not: a phone held upright sees barely half of
	-- what a monitor does across. On those screens the horizontal axis is the one
	-- that clips first, and the piece would slide off the side at the steering
	-- limit. Reading the real viewport aspect covers both axes on any screen.
	--
	-- `halfWidth` and `maximum` default to the ordinary play area's; the PVP map
	-- shot overrides both, because it has to fit however many lanes are in play
	-- across rather than one tower, and on a full board the classic ceiling would
	-- crop the outer two off the sides.
	local function distanceFor(span: number, minimum: number, halfWidth: number?, maximum: number?): number
		local viewport = workspace.CurrentCamera.ViewportSize
		local aspect = if viewport.Y > 0 then viewport.X / viewport.Y else 1
		local forWidth = (halfWidth or Constants.CAMERA_MIN_HALF_WIDTH) / math.max(aspect, 0.1)
		local needed = math.max(span / 2, forWidth) / math.tan(halfAngle)
		return math.clamp(needed, minimum, maximum or Constants.CAMERA_MAX_DISTANCE)
	end

	-- The playing shot: level with the tower top, stretched upward by however much
	-- it takes to keep the piece the holder is aiming inside the frame. A piece
	-- always spawns clear of the tower (and is lifted further if the tower grows
	-- under it), so on a tall piece it can sit well above the ordinary top edge.
	--
	-- The bottom edge stays where it was, so making room for a high piece shows
	-- *more* tower rather than trading it away. With nothing held this reduces
	-- exactly to the old shot: aim CAMERA_AIM_LIFT above the top, stand at
	-- CAMERA_DISTANCE.
	--
	-- `aimX`, `height` and `pieceTop` are all the caller's, so this one shot
	-- serves the classic tower and a PVP lane alike — the framing rules don't
	-- change just because there are five more towers off to the sides.
	local function trackingShot(aimX: number, floorY: number, height: number, pieceTop: number): CFrame
		local towerTop = floorY + math.max(height, Constants.CAMERA_MIN_HEIGHT)
		local bottom = towerTop + aimLift - halfSpan
		local top = math.max(towerTop + aimLift + halfSpan, floorY + pieceTop + Constants.CAMERA_PIECE_MARGIN)
		return shot(aimX, (bottom + top) / 2, distanceFor(top - bottom, distance))
	end

	-- The checkpoint look: frame the whole leg the players just built, from where
	-- the zone started to the top they reached. The server holds `zoneBaseHeight`
	-- and `height` still for the length of the cutscene precisely so this can be
	-- computed from the ordinary state packet instead of a bespoke camera cue.
	local function wideShot(baseTopY: number, data: TowerController.State): CFrame
		local bottom = baseTopY + math.max(data.zoneBaseHeight, 0)
		local top = baseTopY + math.max(data.height, Constants.CAMERA_MIN_HEIGHT)
		local span = math.max(top - bottom, 1) + Constants.CAMERA_CHECKPOINT_PADDING
		return shot(
			0,
			(bottom + top) / 2,
			distanceFor(span, distance * Constants.CAMERA_CHECKPOINT_PULLBACK)
		)
	end

	-- ------------------------------------------------------------------- PVP --
	--
	-- Two shots, and they're the two the mode is about: your own lane, and the
	-- whole board.

	-- The map: every lane *in play* at once, which is what the HUD's camera button
	-- shows during a match.
	--
	-- Framed from the seats that are taken (`PvpLanes.spanOf`) rather than from
	-- all six, so a two-player match is two towers filling the screen instead of
	-- two towers adrift in four empty lanes' worth of sky. The lanes themselves
	-- never move for this — the camera stands closer and off to the side; see the
	-- note on `spanOf`.
	--
	-- Width is what decides the distance here, not height: a full board is 600
	-- studs across and the tallest tower in a three-minute match is a fraction of
	-- that. Hence its own half-width and its own ceiling.
	local function mapShot(floorY: number, tallest: number, centreX: number, halfWidth: number): CFrame
		local top = floorY + math.max(tallest, PvpConstants.MAP_MIN_HEIGHT)
		local span = math.max(top - floorY, 1) + PvpConstants.MAP_PADDING
		return shot(
			centreX,
			(floorY + top) / 2,
			distanceFor(span, distance, halfWidth + PvpConstants.MAP_PADDING, PvpConstants.MAP_MAX_DISTANCE)
		)
	end

	-- Which PVP shot to frame, or nil when no match owns the board.
	--
	-- A player with no lane — spectating, or the match was full when they arrived
	-- — gets the map. It's the only honest shot for them: there is no "their"
	-- tower to ride, and parking on an empty seat would show them a bare platform
	-- for three minutes.
	local function pvpTarget(floorY: number): (CFrame?, number)
		if not PvpController.isActive() then
			return nil, Constants.CAMERA_LERP
		end

		-- One pass over the board: how tall it is, and which seats in it are the
		-- outer two — the map shot is framed from those rather than from all six.
		-- The sentinels are what `spanBetween` reads as "no lanes at all".
		local data = PvpController.GetData()
		local tallest = 0
		local lowest, highest = math.huge, -math.huge
		for _, lane in data.lanes do
			tallest = math.max(tallest, lane.height)
			lowest = math.min(lowest, lane.slot)
			highest = math.max(highest, lane.slot)
		end
		local centreX, halfWidth = PvpLanes.spanBetween(lowest, highest)

		-- The standings are the point of the last ten seconds, so the board is
		-- framed for them whatever the player had the toggle set to.
		if data.phase == PvpConstants.PHASE.RESULTS then
			return mapShot(floorY, tallest, centreX, halfWidth), Constants.CAMERA_CHECKPOINT_LERP
		end

		local mine = PvpController.myLane()
		if overview or mine == nil then
			return mapShot(floorY, tallest, centreX, halfWidth), Constants.CAMERA_CHECKPOINT_LERP
		end
		return trackingShot(PvpLanes.xOf(mine.slot), floorY, mine.height, mine.pieceTop),
			Constants.CAMERA_LERP
	end

	-- How hard the camera should be shaking, 0–1. Ramps from nothing at
	-- STORM_SHAKE_LEAD_SECONDS out to full as the storm lands, then stops: the
	-- server pushes `stormEndsAt` back out the moment it hits, so the rumble ends
	-- on the blast rather than trailing through the wreck.
	--
	-- Squared, so the first twenty of the thirty seconds are a faint unease and
	-- the tell arrives late. A linear ramp reads as "the camera is broken".
	local function shakeIntensity(data: TowerController.State): number
		-- There is no storm in PVP, and `stormEndsAt` is a stale number for the
		-- whole match — the classic clock was set running when the round broke and
		-- nothing has touched it since. Left unguarded it runs out somewhere in the
		-- middle of a match and shakes the camera for a deadline that doesn't
		-- exist.
		if PvpController.isActive() then
			return 0
		end
		local secondsOut = data.stormEndsAt - workspace:GetServerTimeNow()
		if secondsOut <= 0 or secondsOut >= Constants.STORM_SHAKE_LEAD_SECONDS then
			return 0
		end
		local approach = 1 - secondsOut / Constants.STORM_SHAKE_LEAD_SECONDS
		return approach * approach
	end

	task.spawn(function()
		local baseTopY = waitForBaseTop()

		-- The whole tower, current floor to top, with room around it.
		--
		-- Measured from `zoneBaseHeight` — the altitude of the floor the run is
		-- standing on — rather than from the base. Everything below that floor has
		-- been demolished: the server blows the previous platforms away with the
		-- scaffolding under them, so framing from the base would spend most of the
		-- shot on the empty column where old stages used to be and squeeze the
		-- tower the button was pressed to look at into a sliver at the top. On the
		-- first stage the two are the same thing.
		local function overviewShot(baseTopY: number, data: TowerController.State): CFrame
			local floor = baseTopY + math.max(data.zoneBaseHeight, 0)
			-- The minimum is a span *above the floor*, not an absolute altitude:
			-- height is measured from the base, so by floor five it's already
			-- hundreds of studs and a floor on `data.height` would never bite.
			local top = math.max(baseTopY + data.height, floor + Constants.CAMERA_MIN_HEIGHT)
			local span = math.max(top - floor, 1) + Constants.CAMERA_OVERVIEW_PADDING
			return shot(
				0,
				(floor + top) / 2,
				distanceFor(span, distance * Constants.CAMERA_CHECKPOINT_PULLBACK)
			)
		end

		local function target(data: TowerController.State): (CFrame, number)
			-- A PVP match owns the board outright, and it runs *inside* the classic
			-- round break — so this comes first, before the GAMEOVER branch below
			-- would frame a tower that was demolished three minutes ago.
			local pvpShot, pvpRate = pvpTarget(baseTopY)
			if pvpShot ~= nil then
				return pvpShot, pvpRate
			end

			-- Phase wins over the player's toggle. The checkpoint cutscene and the
			-- round break each own the camera and frame something specific; an
			-- overview left switched on must not eat that shot.
			if data.phase == Constants.PHASE.CHECKPOINT or data.phase == Constants.PHASE.GAMEOVER then
				return wideShot(baseTopY, data), Constants.CAMERA_CHECKPOINT_LERP
			end
			if overview then
				return overviewShot(baseTopY, data), Constants.CAMERA_CHECKPOINT_LERP
			end
			return trackingShot(0, baseTopY, data.height, data.pieceTop), Constants.CAMERA_LERP
		end

		local camera = workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = Constants.CAMERA_FOV
		-- The smoothed shot, kept apart from what the camera is actually showing.
		-- The shake is composed on top of this rather than written into it: fold
		-- the jitter back into the value the next frame lerps from and the shake
		-- feeds into the follow, which turns a rumble into a drift.
		local base = target(TowerController.GetData())
		camera.CFrame = base

		local shakeClock = 0

		RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value, function(deltaTime)
			local current = workspace.CurrentCamera
			-- Respawns and Studio can hand the camera back to the default script;
			-- reclaiming it each frame is cheaper than watching for that.
			if current.CameraType ~= Enum.CameraType.Scriptable then
				current.CameraType = Enum.CameraType.Scriptable
			end

			local data = TowerController.GetData()
			-- Framerate-independent exponential follow: the tower can grow by a
			-- whole block between frames and this stays smooth either way. The
			-- checkpoint pull-back returns a slower rate, so the move eases out
			-- instead of tracking.
			local goal, rate = target(data)
			local alpha = 1 - math.exp(-rate * deltaTime)
			base = base:Lerp(goal, alpha)

			local intensity = shakeIntensity(data)
			if intensity <= 0 then
				current.CFrame = base
				return
			end

			-- Two different slices of the noise field so the axes don't move
			-- together, which would read as a slide rather than a shake.
			shakeClock += deltaTime * Constants.STORM_SHAKE_FREQUENCY
			local offset = Vector3.new(
				math.noise(shakeClock, 0.5) * Constants.STORM_SHAKE_OFFSET * intensity,
				math.noise(0.5, shakeClock) * Constants.STORM_SHAKE_OFFSET * intensity,
				0
			)
			local roll = math.noise(shakeClock, shakeClock)
				* math.rad(Constants.STORM_SHAKE_TILT_DEGREES)
				* intensity
			current.CFrame = base * CFrame.new(offset) * CFrame.Angles(0, 0, roll)
		end)
	end)
end

return TowerCameraController
