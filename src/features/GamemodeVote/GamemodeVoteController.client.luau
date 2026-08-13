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

local audio = require(ReplicatedStorage.Shared.Boil).audio
local Constants = require(ReplicatedStorage.Features.GamemodeVote.Constants)
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

-- Which option each voter was on as of the last packet, and which poll that was.
-- A stamp *lands* when a voter appears or moves — which is exactly when the view
-- mounts a new one, since it keys stamps by user id and a move is a real
-- unmount. Diffing here rather than in the view keeps the cue off the render
-- path: a re-render for any other reason would otherwise replay it.
local stamped: { [number]: string } = {}
local stampedPoll = 0

local function playStamps(next: State)
	-- No poll running: nothing has landed, and the next one starts clean.
	if next.endsAt == 0 then
		table.clear(stamped)
		stampedPoll = 0
		return
	end

	-- First sight of this poll. Absorb whatever is already on the board without
	-- a sound — this is the packet a player joining mid-vote gets, and it would
	-- otherwise open with a burst of stamps for votes cast before they arrived.
	if next.endsAt ~= stampedPoll then
		stampedPoll = next.endsAt
		table.clear(stamped)
		for _, voter in next.voters do
			stamped[voter.userId] = voter.optionId
		end
		return
	end

	local landed = false
	for _, voter in next.voters do
		if stamped[voter.userId] ~= voter.optionId then
			stamped[voter.userId] = voter.optionId
			landed = true
		end
	end

	-- Taking a vote back unmounts a stamp rather than landing one, so it makes no
	-- sound — but it does have to stop the voter's old choice counting as still
	-- stamped, or re-voting for it would be silent.
	local present: { [number]: boolean } = {}
	for _, voter in next.voters do
		present[voter.userId] = true
	end
	for userId in stamped do
		if not present[userId] then
			stamped[userId] = nil
		end
	end

	-- Once per packet, however many landed in it. Votes arrive one at a time in
	-- practice, and firing per-voter on the packet where several do would read as
	-- a stutter rather than as several people voting.
	if landed then
		audio.playCue(Constants.STAMP_SOUND, { volumeScale = Constants.STAMP_VOLUME })
	end
end

function GamemodeVoteController.Start()
	Packets.State.listen(function(next)
		data = next
		playStamps(next)
		GamemodeVoteController.DataChanged:Fire(data)
	end)
end

return GamemodeVoteController
