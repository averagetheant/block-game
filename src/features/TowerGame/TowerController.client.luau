-- Client surface for TowerGame: the replicated state store plus the four intent
-- actions every presentation calls.
--
-- The store deliberately matches the `GetData()` + `DataChanged` shape the shared
-- `useReplica` hook expects, so views subscribe to it exactly like they subscribe
-- to PlayerData — no bespoke useEffect in the view.
--
-- Intents don't apply anything locally. The held piece is a server-owned Model,
-- so the authoritative move *is* the visible move; the local turn check here only
-- spares the wire pointless packets.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Packages.Signal)

local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)
local Packets = require(ReplicatedStorage.Features.TowerGame.Packets)

-- Client-realm sibling. Required for the two mode-routing answers below only —
-- the classic store itself knows nothing about PVP.
local PvpController = require(script.Parent.PvpController)

export type State = {
	phase: number,
	holderUserId: number,
	turnEndsAt: number,
	height: number,
	maxHeight: number,
	-- Top of the piece being aimed, studs above the base; 0 when nobody holds one.
	pieceTop: number,
	blockCount: number,
	shapeId: number,
	blockTypeId: number,
	nextShapeId: number,
	order: { number },
	-- Who goes again after the current turn (Double Turn), 0 for nobody.
	repeatUserId: number,
	targetHeight: number,
	zoneBaseHeight: number,
	stormEndsAt: number,
	checkpoints: number,
	zoneId: number,
	zoneSky: number,
	-- The stage's clock lengths. Constants until a gamemode vote changes them.
	turnSeconds: number,
	stormSeconds: number,
}

local TowerController = {}

TowerController.DataChanged = Signal.new()

local data: State = {
	phase = Constants.PHASE.IDLE,
	holderUserId = 0,
	turnEndsAt = 0,
	height = 0,
	maxHeight = 0,
	pieceTop = 0,
	blockCount = 0,
	shapeId = 0,
	blockTypeId = 0,
	nextShapeId = 0,
	order = {},
	repeatUserId = 0,
	targetHeight = Constants.STORM_FIRST_TARGET,
	zoneBaseHeight = 0,
	stormEndsAt = 0,
	checkpoints = 0,
	zoneId = 1,
	zoneSky = 1,
	turnSeconds = Constants.TURN_SECONDS,
	stormSeconds = Constants.STORM_SECONDS,
}

function TowerController.GetData(): State
	return data
end

function TowerController.isMyTurn(): boolean
	return data.holderUserId ~= 0 and data.holderUserId == Players.LocalPlayer.UserId
end

-- Whether this player has a piece in the air, in whichever mode is running.
--
-- The aiming and input controllers gate on this rather than on `isMyTurn`,
-- because "my turn" is a statement about a queue and PVP has none — everybody is
-- holding a piece at once. In the classic game the two are the same answer.
function TowerController.isAiming(): boolean
	if PvpController.isActive() then
		return PvpController.isHolding()
	end
	return TowerController.isMyTurn()
end

-- The world X that a placement's `x` is measured from: this player's own lane
-- centre. 0 for the classic game, which is one lane at the arena's origin.
--
-- Every number the client sends the server is relative to this, which is what
-- makes the server's clamp the same clamp in both modes — and what stops a
-- client aiming into somebody else's lane by sending a bigger number.
function TowerController.laneOriginX(): number
	return PvpController.laneOriginX()
end

-- Seconds left before the piece this player is aiming drops itself.
function TowerController.pieceSecondsLeft(): number
	if not PvpController.isActive() then
		return TowerController.secondsLeft()
	end
	local lane = PvpController.myLane()
	if lane == nil or not lane.holding or lane.pieceEndsAt <= 0 then
		return 0
	end
	return math.max(0, lane.pieceEndsAt - workspace:GetServerTimeNow())
end

-- Seconds left on the current turn. `turnEndsAt` is a server-time stamp, so this
-- stays honest without the server ticking a countdown at us.
function TowerController.secondsLeft(): number
	if data.turnEndsAt <= 0 then
		return 0
	end
	return math.max(0, data.turnEndsAt - workspace:GetServerTimeNow())
end

-- Seconds left before the storm closes the current stage.
function TowerController.stormSecondsLeft(): number
	if data.stormEndsAt <= 0 then
		return 0
	end
	return math.max(0, data.stormEndsAt - workspace:GetServerTimeNow())
end

-- Report where the holder has the piece. TowerAimController owns the numbers and
-- the cadence; this is just the wire. The server clamps whatever arrives.
function TowerController.place(x: number, turns: number)
	if not TowerController.isAiming() then
		return
	end
	Packets.Place.send({ x = x, turns = turns })
end

-- Drop it, at this placement. Carrying the placement with the drop is what makes
-- the piece land where the holder saw it rather than where the last stream
-- update happened to reach.
function TowerController.release(x: number, turns: number)
	if not TowerController.isAiming() then
		return
	end
	Packets.Release.send({ x = x, turns = turns })
end

function TowerController.Start()
	Packets.State.listen(function(payload)
		data = payload :: State
		TowerController.DataChanged:Fire(data)
	end)
end

return TowerController
