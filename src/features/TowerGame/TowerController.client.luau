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

export type State = {
	phase: number,
	holderUserId: number,
	turnEndsAt: number,
	height: number,
	maxHeight: number,
	blockCount: number,
	shapeId: number,
	nextShapeId: number,
	queueCount: number,
	targetHeight: number,
	stormEndsAt: number,
	checkpoints: number,
}

local TowerController = {}

TowerController.DataChanged = Signal.new()

local data: State = {
	phase = Constants.PHASE.IDLE,
	holderUserId = 0,
	turnEndsAt = 0,
	height = 0,
	maxHeight = 0,
	blockCount = 0,
	shapeId = 0,
	nextShapeId = 0,
	queueCount = 0,
	targetHeight = Constants.STORM_FIRST_TARGET,
	stormEndsAt = 0,
	checkpoints = 0,
}

function TowerController.GetData(): State
	return data
end

function TowerController.isMyTurn(): boolean
	return data.holderUserId ~= 0 and data.holderUserId == Players.LocalPlayer.UserId
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

-- Steering is a held direction, not a step: -1, 0 or 1. The server integrates
-- the movement, so this fires twice per swipe (press and release) rather than
-- once per stud.
function TowerController.setSteer(dir: number)
	if not TowerController.isMyTurn() then
		return
	end
	Packets.Steer.send({ dir = dir })
end

-- Touch has no key-up, so a tap sends a fixed-length pulse instead. One tap is
-- worth STEER_SPEED × TOUCH_NUDGE_SECONDS studs of glide.
function TowerController.nudge(dir: number)
	if not TowerController.isMyTurn() then
		return
	end
	Packets.Steer.send({ dir = dir })
	task.delay(Constants.TOUCH_NUDGE_SECONDS, function()
		-- Not gated on isMyTurn: if the turn ended mid-pulse we still want the
		-- server to hear the release.
		Packets.Steer.send({ dir = 0 })
	end)
end

function TowerController.rotate(clockwise: boolean?)
	if not TowerController.isMyTurn() then
		return
	end
	Packets.Spin.send({ clockwise = clockwise ~= false })
end

function TowerController.drop()
	if not TowerController.isMyTurn() then
		return
	end
	Packets.Release.send({ instant = true })
end

function TowerController.Start()
	Packets.State.listen(function(payload)
		data = payload :: State
		TowerController.DataChanged:Fire(data)
	end)
end

return TowerController
