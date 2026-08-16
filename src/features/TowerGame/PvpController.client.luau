-- Client surface for the PVP round: the replicated match state, and the two
-- questions the rest of the client asks about it.
--
-- Shaped like TowerController on purpose — a `GetData()` + `DataChanged` pair, so
-- `PvpView` subscribes to it through the same `useReplica` hook every other view
-- uses and needs no bespoke effect of its own.
--
-- The two questions are the interesting part, because they're what let the aiming
-- and camera code stay one implementation across both modes:
--
--   * `myLane()` — the lane this player is building in, or nil. Whether they're
--     holding a piece, how tall their tower is, and where on the wire their own
--     row is, all come out of it.
--   * `laneOriginX()` — the world X their lane's centre line stands on, which is
--     0 in classic and up to ±325 in PVP. Every placement number the client
--     produces is measured from it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Packages.Signal)

local PvpConstants = require(ReplicatedStorage.Features.TowerGame.PvpConstants)
local PvpLanes = require(ReplicatedStorage.Features.TowerGame.PvpLanes)
local PvpPackets = require(ReplicatedStorage.Features.TowerGame.PvpPackets)

export type Lane = {
	userId: number,
	slot: number,
	height: number,
	blockCount: number,
	holding: boolean,
	pieceTop: number,
	pieceEndsAt: number,
	shapeId: number,
	blockTypeId: number,
}

export type State = {
	phase: number,
	endsAt: number,
	matchSeconds: number,
	zoneId: number,
	zoneSky: number,
	lanes: { Lane },
}

local PvpController = {}

-- Ahead of the aim and camera controllers (10 and up), because both ask this
-- file which lane they're in before they draw their first frame.
PvpController.Priority = 5

PvpController.DataChanged = Signal.new()

local data: State = {
	phase = PvpConstants.PHASE.OFF,
	endsAt = 0,
	matchSeconds = PvpConstants.MATCH_SECONDS,
	zoneId = 1,
	zoneSky = 1,
	lanes = {},
}

function PvpController.GetData(): State
	return data
end

-- Whether a match owns the board. Everything else in the client that has to
-- behave differently — the HUD it mounts, the shot the camera frames, where a
-- placement is measured from — hangs off this one answer.
function PvpController.isActive(): boolean
	return data.phase ~= PvpConstants.PHASE.OFF
end

-- This player's lane, or nil if they aren't in the match (spectating, or the
-- match filled up before they arrived).
function PvpController.myLane(): Lane?
	local userId = Players.LocalPlayer.UserId
	for _, lane in data.lanes do
		if lane.userId == userId then
			return lane
		end
	end
	return nil
end

-- The centre line every placement this player makes is measured from.
--
-- 0 whenever they aren't in a PVP lane, which is exactly the classic game's
-- answer — so the callers never branch on the mode, they just add this in.
function PvpController.laneOriginX(): number
	local lane = PvpController.myLane()
	return if lane then PvpLanes.xOf(lane.slot) else 0
end

-- Whether this player is aiming a piece right now.
function PvpController.isHolding(): boolean
	local lane = PvpController.myLane()
	return lane ~= nil and lane.holding
end

-- Seconds left on whatever clock the current phase is running. `endsAt` is a
-- server-time stamp, so this stays honest without a packet a second.
function PvpController.secondsLeft(): number
	if data.endsAt <= 0 then
		return 0
	end
	return math.max(0, data.endsAt - workspace:GetServerTimeNow())
end

-- The lanes tallest first, which is the order the standings are read in. Sorted
-- here rather than on the server so the wire stays in slot order — the map shot
-- and the lane strip both want the seats in the order they physically sit, and a
-- list that reorders itself every time somebody overtakes would make either of
-- them unreadable.
function PvpController.standings(): { Lane }
	local sorted = table.clone(data.lanes)
	table.sort(sorted, function(a, b)
		return a.height > b.height
	end)
	return sorted
end

-- This player's place in the standings, 1-based, or 0 if they aren't playing.
function PvpController.myRank(): number
	local userId = Players.LocalPlayer.UserId
	for rank, lane in PvpController.standings() do
		if lane.userId == userId then
			return rank
		end
	end
	return 0
end

function PvpController.Start()
	PvpPackets.State.listen(function(payload)
		data = payload :: State
		PvpController.DataChanged:Fire(data)
	end)
end

return PvpController
