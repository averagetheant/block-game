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
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Features.GamemodeVote.Constants)
local Packets = require(ReplicatedStorage.Features.GamemodeVote.Packets)
local Registry = require(ReplicatedStorage.Features.GamemodeVote.Registry)

-- The 2x Votes gamepass (registered as a card in this feature's Store.luau).
-- Ownership is asked here rather than sent by the client for the obvious reason:
-- a weight the client claimed would be a tally the client wrote.
local StoreService = require(ServerScriptService.Features.Store.StoreService)

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
-- userId -> what that vote counts for. Stamped when the vote is cast rather than
-- read at the count, so buying the pass mid-poll doesn't retroactively reweigh a
-- stamp that's been sitting on a panel — re-vote and it counts double.
local weights: { [number]: number } = {}

-- How much one player's vote counts for. One stamp either way: the screen shows
-- presence, and a second headshot for the same player would read as a second
-- player rather than as a heavier vote.
local function weightOf(player: Player): number
	if StoreService.ownsGamepass(player, Constants.GAMEPASS_DOUBLE_VOTE) then
		return Constants.DOUBLE_VOTE_WEIGHT
	end
	return 1
end

local function payload()
	local voters = {}
	for userId, optionId in votes do
		table.insert(voters, { userId = userId, optionId = optionId, weight = weights[userId] or 1 })
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
		weights[player.UserId] = nil
	else
		votes[player.UserId] = optionId
		weights[player.UserId] = weightOf(player)
	end
	broadcast()
end

function GamemodeVoteService.isActive(): boolean
	return endsAt ~= 0
end

-- The ballot for one poll: every pinned mode, then random picks from the rest up
-- to BALLOT_SIZE, in display order.
--
-- Rolled per vote rather than fixed, so a game with more modes registered than
-- fit on a ballot shows a different pair each round instead of burying the extra
-- ones forever. Which mode is pinned is the registering feature's call — this
-- file knows nothing about any of them.
--
-- Returns the ids only; the client looks the rest up in its own Registry copy.
local function buildBallot(): { string }
	local pinned: { Registry.Gamemode } = {}
	local rest: { Registry.Gamemode } = {}
	for _, mode in Registry.list() do
		table.insert(if mode.pinned then pinned else rest, mode)
	end

	-- Partial Fisher-Yates: shuffle only as far as the slots that are left, which
	-- for a handful of modes is the whole list anyway and stays correct if that
	-- list ever grows.
	local slots = math.max(Constants.BALLOT_SIZE - #pinned, 0)
	for index = 1, math.min(slots, #rest) do
		local pick = math.random(index, #rest)
		rest[index], rest[pick] = rest[pick], rest[index]
	end

	local chosen = pinned
	for index = 1, math.min(slots, #rest) do
		table.insert(chosen, rest[index])
	end

	-- Back into display order, so the pinned mode sits where its `order` says
	-- rather than merely first-because-pinned.
	table.sort(chosen, function(a, b)
		local orderA = a.order or 0
		local orderB = b.order or 0
		if orderA ~= orderB then
			return orderA < orderB
		end
		return a.name < b.name
	end)

	local ids = {}
	for _, mode in chosen do
		table.insert(ids, mode.id)
	end
	return ids
end

-- Highest tally wins. Ties break randomly among the tied, and a poll nobody
-- voted in picks at random too — the caller always gets a mode back, so it
-- never has to carry a "what if they all abstained" branch.
local function pickWinner(): string
	local counts: { [string]: number } = {}
	for userId, optionId in votes do
		counts[optionId] = (counts[optionId] or 0) + (weights[userId] or 1)
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

	options = buildBallot()
	if #options == 0 then
		return nil
	end
	votes = {}
	weights = {}
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
	weights = {}
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
		weights[player.UserId] = nil
		broadcast()
	end)
end

return GamemodeVoteService
