-- Client surface for GamemodeVote: the replicated poll plus the one intent a
-- presentation calls.
--
-- The store matches the `GetData()` + `DataChanged` shape the shared
-- `useReplica` hook expects, so the view subscribes exactly like it would to
-- PlayerData — no bespoke useEffect in the view.
--
-- `castVote` doesn't apply anything locally. The server owns the tally, and the
-- round trip is a frame or two; showing a vote that might be rejected would be
-- worse than showing it a moment late.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Packages.Signal)

local Packets = require(ReplicatedStorage.Features.GamemodeVote.Packets)

export type Voter = {
	userId: number,
	optionId: string,
}

export type State = {
	-- Server-time stamp the poll closes at; 0 when no vote is running.
	endsAt: number,
	-- "" while voting, then the winning gamemode id.
	winnerId: string,
	options: { string },
	voters: { Voter },
}

local GamemodeVoteController = {}

GamemodeVoteController.DataChanged = Signal.new()

local data: State = {
	endsAt = 0,
	winnerId = "",
	options = {},
	voters = {},
}

function GamemodeVoteController.GetData(): State
	return data
end

function GamemodeVoteController.isActive(): boolean
	return data.endsAt ~= 0
end

-- Seconds left on the poll. `endsAt` is a server-time stamp, so this is computed
-- locally every frame instead of being shipped once a second. Clamped at 0: the
-- stamp stays in the past through the result window.
function GamemodeVoteController.secondsLeft(): number
	if data.endsAt == 0 then
		return 0
	end
	return math.max(0, data.endsAt - workspace:GetServerTimeNow())
end

-- The one intent. Sending the id you already hold takes the vote back — the
-- server reads it that way, so the view has no un-vote button to render.
function GamemodeVoteController.castVote(optionId: string)
	if typeof(optionId) ~= "string" or optionId == "" then
		return
	end
	Packets.Cast.send({ optionId = optionId })
end

function GamemodeVoteController.Start()
	Packets.State.listen(function(next)
		data = next
		GamemodeVoteController.DataChanged:Fire(data)
	end)
end

return GamemodeVoteController
