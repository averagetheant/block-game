-- Client core for VoiceChat: builds this listener's audio graph, and works out
-- who is currently talking.
--
-- Headless (see docs/game/headless-core.md) — it wires audio and holds state,
-- and it draws nothing. VoiceView is what turns "these three are talking" into
-- chips in the corner.
--
-- ## Why the routing lives here
--
-- A microphone is server-owned (VoiceService parents one AudioDeviceInput to
-- each player); *what you hear* is not. Every client builds its own mix, so the
-- graph below is local instances only — nothing here replicates, and no client
-- can change what anyone else hears.
--
-- The graph is deliberately flat:
--
--     every other player's AudioDeviceInput --> our AudioDeviceOutput
--     every player's AudioDeviceInput (incl. ours) --> an AudioAnalyzer
--
-- No emitters, no listener, no positions. Distance can't attenuate a wire, so
-- the whole server is audible at full volume regardless of where anyone stands
-- — that's the "universal" part, and it's why default voice has to be off (see
-- Constants).
--
-- Our own microphone is wired to an analyzer but *not* to the output: you want
-- to see yourself in the list when you talk, and you very much do not want to
-- hear yourself say it a moment later.
--
-- ## Why an analyzer rather than asking whether someone is speaking
--
-- There's no "is this player talking" API. AudioAnalyzer.RmsLevel is the actual
-- loudness of the stream we're already receiving, so it answers the question
-- directly, and it answers it the same way for everyone including us.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Signal = require(ReplicatedStorage.Packages.Signal)
local Constants = require(ReplicatedStorage.Features.VoiceChat.Constants)

local VoiceController = {}

-- Feature band. Nothing waits on the audio graph being up.
VoiceController.Priority = 60

export type Speaker = {
	userId: number,
	displayName: string,
}

-- Fires when the *set* of speakers changes — someone starts, someone stops,
-- someone leaves. Not on every level change: the chips animate their own rings
-- off `levelOf`, so a re-render per sample would be work for nothing.
VoiceController.Changed = Signal.new()

type Entry = {
	player: Player,
	-- The input this graph was built on, so a refresh can tell "still the right
	-- microphone" from "a different one is live now".
	input: AudioDeviceInput,
	analyzer: AudioAnalyzer,
	-- Everything we created for this player, in one folder. Cleanup is one
	-- Destroy, which is what keeps a leave (or a re-created input) from leaving
	-- a dead wire in the graph.
	graph: Folder,
	-- Counted as talking until this clock time. Extended while they're loud; the
	-- gap between it and now is what rides over the pauses in speech.
	loudUntil: number,
	-- When this run of talking began, so the column keeps a stable order rather
	-- than reshuffling every time someone pauses.
	startedAt: number,
}

local entries: { [Player]: Entry } = {}
local speakers: { Speaker } = {}
-- Mirror of the live levels keyed by user id, so the UI can ask for one without
-- holding a Player.
local levels: { [number]: number } = {}

local output: AudioDeviceOutput? = nil
local container: Folder? = nil

-- Everyone currently talking, longest-running first.
function VoiceController.speakers(): { Speaker }
	return speakers
end

-- A talker's current microphone level, 0-1 against Constants.LEVEL_FULL. Zero
-- for anyone silent or unknown, so a caller never has to check first.
function VoiceController.levelOf(userId: number): number
	return math.clamp((levels[userId] or 0) / Constants.LEVEL_FULL, 0, 1)
end

local function wire(source: Instance, target: Instance, parent: Instance)
	local link = Instance.new("Wire")
	link.SourceInstance = source
	link.TargetInstance = target
	link.Parent = parent
end

local function detach(player: Player)
	local entry = entries[player]
	if entry == nil then
		return
	end
	entry.graph:Destroy()
	entries[player] = nil
	levels[player.UserId] = nil
end

-- Put a player's microphone into our mix and under a meter. Rebuilds rather than
-- adds: an input can be re-created (and a removal we didn't see would leave the
-- old wires behind), and two sets of wires for one voice would play it twice.
local function attach(player: Player, input: AudioDeviceInput)
	detach(player)

	local graph = Instance.new("Folder")
	graph.Name = `Voice_{player.UserId}`
	graph.Parent = container

	local analyzer = Instance.new("AudioAnalyzer")
	-- We only ever read RmsLevel; the spectrum is per-frame FFT work nobody here
	-- consumes.
	analyzer.SpectrumEnabled = false
	analyzer.Parent = graph
	wire(input, analyzer, graph)

	-- Hearing your own microphone played back is the one thing this graph must
	-- never do.
	if player ~= Players.LocalPlayer and output ~= nil then
		wire(input, output, graph)
	end

	entries[player] = {
		player = player,
		input = input,
		analyzer = analyzer,
		graph = graph,
		loudUntil = 0,
		startedAt = 0,
	}
end

-- Which of a player's inputs is carrying their voice.
--
-- There can be more than one for a moment: the engine makes its own when the
-- voice session connects, and VoiceService may have made one before it. `Active`
-- is what separates the live microphone from the inert instance beside it, and
-- metering the wrong one is silent forever rather than obviously broken — so it
-- decides, and an inactive input is only a fallback until one wakes up.
local function liveInput(player: Player): AudioDeviceInput?
	local fallback: AudioDeviceInput? = nil
	for _, child in player:GetChildren() do
		if not child:IsA("AudioDeviceInput") then
			continue
		end
		if child.Active then
			return child
		end
		fallback = fallback or child
	end
	return fallback
end

-- Point this player's graph at whichever input is live now, rebuilding only when
-- that's actually changed.
local function refresh(player: Player)
	local input = liveInput(player)
	if input == nil then
		detach(player)
		return
	end

	local entry = entries[player]
	if entry ~= nil and entry.input == input then
		return
	end
	attach(player, input)
end

-- Follow a player's microphone. It may not exist yet — the engine creates it as
-- the voice session connects, well after the Player instance lands — and the one
-- that matters can change afterwards, so this listens for both the arrival and
-- the moment an input goes live.
local function watch(player: Player)
	local function track(child: Instance)
		if not child:IsA("AudioDeviceInput") then
			return
		end
		child:GetPropertyChangedSignal("Active"):Connect(function()
			refresh(player)
		end)
		refresh(player)
	end

	for _, child in player:GetChildren() do
		track(child)
	end
	player.ChildAdded:Connect(track)

	player.ChildRemoved:Connect(function(child: Instance)
		if child:IsA("AudioDeviceInput") then
			refresh(player)
		end
	end)
end

-- Whether two speaker lists name the same people in the same order. Compared by
-- hand rather than rebuilt-and-diffed because this runs at POLL_INTERVAL and the
-- answer is almost always "no change".
local function sameSpeakers(a: { Speaker }, b: { Speaker }): boolean
	if #a ~= #b then
		return false
	end
	for index, speaker in a do
		if b[index].userId ~= speaker.userId then
			return false
		end
	end
	return true
end

-- Sample every meter, then rebuild the list of who counts as talking.
local function poll(now: number)
	local talking: { Entry } = {}

	for player, entry in entries do
		local level = entry.analyzer.RmsLevel
		levels[player.UserId] = level

		if level >= Constants.SPEAKING_RMS then
			-- A fresh run of talking, rather than a continuation across a pause.
			if now >= entry.loudUntil then
				entry.startedAt = now
			end
			entry.loudUntil = now + Constants.HOLD_SECONDS
		end

		if now < entry.loudUntil then
			table.insert(talking, entry)
		else
			-- Silent players read as zero rather than as their last syllable,
			-- which matters for the fade-out on a chip that's on its way off.
			levels[player.UserId] = 0
		end
	end

	table.sort(talking, function(a: Entry, b: Entry): boolean
		if a.startedAt == b.startedAt then
			return a.player.UserId < b.player.UserId
		end
		return a.startedAt < b.startedAt
	end)

	local updated: { Speaker } = table.create(#talking)
	for index, entry in talking do
		updated[index] = {
			userId = entry.player.UserId,
			displayName = entry.player.DisplayName,
		}
	end

	if sameSpeakers(updated, speakers) then
		return
	end
	speakers = updated
	VoiceController.Changed:Fire()
end

function VoiceController.Start()
	local graphs = Instance.new("Folder")
	graphs.Name = Constants.GRAPH_NAME
	graphs.Parent = SoundService
	container = graphs

	-- Our mixdown. Local, and ours alone — with default voice off there is no
	-- other output, and with it on this one simply carries the wires we made.
	local mix = Instance.new("AudioDeviceOutput")
	mix.Name = Constants.OUTPUT_NAME
	mix.Parent = graphs
	output = mix

	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(detach)

	-- Sampled on a timer rather than per frame: nothing here is frame-accurate,
	-- and reading a meter for every player in a full server every frame is real
	-- work for an answer that changes a few times a second.
	local since = 0
	RunService.Heartbeat:Connect(function(deltaTime: number)
		since += deltaTime
		if since < Constants.POLL_INTERVAL then
			return
		end
		since = 0
		poll(os.clock())
	end)
end

return VoiceController
