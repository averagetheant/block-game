-- Server core for the vote: runs the poll, owns the tally, picks the winner.
--
-- `startVote()` yields for the length of the poll and returns the winning
-- gamemode id, so the caller reads as a step in whatever sequence it's running
-- ("clear the stage, ask the players what's next, start the stage") rather than
-- as a callback dropped into the middle of it.
--
-- The tally is server-side only. Clients send a preference; they never send a
-- count, and the winner is decided here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Features.GamemodeVote.Constants)
local Packets = require(ReplicatedStorage.Features.GamemodeVote.Packets)
local Registry = require(ReplicatedStorage.Features.GamemodeVote.Registry)

local GamemodeVoteService = {}

-- No dependency on another service's startup; the vote only does anything once
-- something calls startVote().
GamemodeVoteService.Priority = 5

-- Poll state. `endsAt` doubles as the "a vote is up" flag — 0 means closed,
-- which is exactly what the client keys its frame off.
local endsAt = 0
local winnerId = ""
local options: { string } = {}
-- userId -> gamemode id. Keyed by user id rather than Player because the screen
-- shows a vote as that player's headshot, and the id is what fetches it.
local votes: { [number]: string } = {}

local function payload()
	local voters = {}
	for userId, optionId in votes do
		table.insert(voters, { userId = userId, optionId = optionId })
	end
	-- Stable order so a client re-render can't shuffle the headshots around a
	-- panel for no reason.
	table.sort(voters, function(a, b)
		return a.userId < b.userId
	end)

	return {
		endsAt = endsAt,
		winnerId = winnerId,
		options = options,
		voters = voters,
	}
end

local function broadcast()
	Packets.State.sendToAll(payload())
end

local function isOption(optionId: string): boolean
	return table.find(options, optionId) ~= nil
end

-- The core intent every presentation routes through. Validation lives here, not
-- in the caller: the packet handler is dumb, and so is the view.
function GamemodeVoteService.castVote(player: Player, optionId: string)
	if endsAt == 0 or winnerId ~= "" then
		return
	end
	if workspace:GetServerTimeNow() >= endsAt then
		return
	end
	if typeof(optionId) ~= "string" or not isOption(optionId) then
		return
	end

	-- Voting for what you already picked takes it back, so the screen needs no
	-- separate un-vote affordance.
	if votes[player.UserId] == optionId then
		votes[player.UserId] = nil
	else
		votes[player.UserId] = optionId
	end
	broadcast()
end

function GamemodeVoteService.isActive(): boolean
	return endsAt ~= 0
end

-- Highest tally wins. Ties break randomly among the tied, and a poll nobody
-- voted in picks at random too — the caller always gets a mode back, so it
-- never has to carry a "what if they all abstained" branch.
local function pickWinner(): string
	local counts: { [string]: number } = {}
	for _, optionId in votes do
		counts[optionId] = (counts[optionId] or 0) + 1
	end

	local best = 0
	local leaders: { string } = {}
	for _, optionId in options do
		local count = counts[optionId] or 0
		if count > best then
			best = count
			leaders = { optionId }
		elseif count == best then
			table.insert(leaders, optionId)
		end
	end

	return leaders[math.random(1, #leaders)]
end

-- Opens a poll and yields until it's resolved. Returns the winning gamemode id,
-- or nil when there was nothing to vote on (no gamemodes registered) or a vote
-- was already running — in both cases the caller carries on with its default.
function GamemodeVoteService.startVote(): string?
	if endsAt ~= 0 then
		warn("[GamemodeVote] startVote() called while a vote was already open")
		return nil
	end

	local modes = Registry.list()
	if #modes == 0 then
		return nil
	end

	options = {}
	for _, mode in modes do
		table.insert(options, mode.id)
	end
	votes = {}
	winnerId = ""
	endsAt = workspace:GetServerTimeNow() + Constants.VOTE_SECONDS
	broadcast()

	task.wait(Constants.VOTE_SECONDS)

	-- The result window: the poll is closed and the winner is on screen, but the
	-- frame is still up. `endsAt` stays put (now in the past) so clients keep
	-- showing it instead of tearing the screen down the instant the clock hits 0.
	winnerId = pickWinner()
	broadcast()
	task.wait(Constants.RESULT_SECONDS)

	local result = winnerId
	endsAt = 0
	winnerId = ""
	votes = {}
	options = {}
	broadcast()

	return result
end

function GamemodeVoteService.Start()
	Packets.Cast.listen(function(data, player)
		GamemodeVoteService.castVote(player, data.optionId)
	end)

	-- A player who joins mid-poll should see it. State only goes out on change,
	-- so without this they'd sit through the vote looking at nothing.
	Players.PlayerAdded:Connect(function(player)
		if endsAt == 0 then
			return
		end
		Packets.State.sendTo(payload(), player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		-- A leaver's headshot shouldn't sit on a panel voting in a round they're
		-- not in, so the vote goes with them.
		if votes[player.UserId] == nil then
			return
		end
		votes[player.UserId] = nil
		broadcast()
	end)
end

return GamemodeVoteService
