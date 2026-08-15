-- Server half of VoiceChat: make sure every player has exactly one microphone
-- the rest of the server can wire itself to, and say so loudly when the place is
-- configured in a way that stops that working.
--
-- That's the whole job. The server owns *whose* microphone exists, because an
-- AudioDeviceInput has to be created by the server to be trusted with a Player;
-- it owns none of the mixing, because who hears what is a per-listener question
-- and lives on the client (see VoiceController).
--
-- Who creates the input depends on the place. With `EnableDefaultVoice` on the
-- engine makes one per player as their voice session connects, and we must not
-- add a second: only the engine's carries the live stream, so the spare sits at
-- `Active = false` forever and anything metering it hears silence. With default
-- voice off — the configuration this feature wants — nothing makes one, so we do.
--
-- Which means this file's real problem is *knowing which place it's in*, and the
-- answer isn't available when it needs it: `VoiceChatService`'s place settings
-- throw on read until the service has initialized, which is after the first
-- players have joined. So the setting is resolved by retrying in the background,
-- and until it answers nobody is given a microphone by us. The default when it
-- never answers is to provision anyway: a spare input we then drop is
-- recoverable, a server where nobody has a microphone at all is not.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VoiceChatService = game:GetService("VoiceChatService")

local Constants = require(ReplicatedStorage.Features.VoiceChat.Constants)

local VoiceService = {}

-- Feature band; nothing else waits on voice being up.
VoiceService.Priority = 60

-- Whether *we* are the ones making microphones here. False until the place
-- settings have been read, so we never race the engine on the strength of a
-- read that hasn't happened yet.
local provisioning = false

-- Read a VoiceChatService property without assuming it's readable yet. Early in
-- the session these throw rather than returning nil, so nil here means "don't
-- know", not "off".
local function setting(name: string): any?
	local ok, value = pcall(function()
		return (VoiceChatService :: any)[name]
	end)
	if not ok then
		return nil
	end
	return value
end

-- Keep asking until the place settings are readable. Returns nil if they never
-- are, which callers treat as "don't know" rather than as a value.
local function resolveSetting(name: string): any?
	for _ = 1, Constants.SETTING_ATTEMPTS do
		local value = setting(name)
		if value ~= nil then
			return value
		end
		task.wait(Constants.SETTING_RETRY_SECONDS)
	end
	return nil
end

-- The two place settings this feature depends on. Neither can be fixed from a
-- script — they're saved in the place, set in Studio's Explorer — so the only
-- useful thing to do about a wrong one is name it precisely.
local function checkConfiguration(defaultVoice: any?)
	if setting("UseAudioApi") == Enum.AudioApiRollout.Disabled then
		warn(
			"[VoiceChat] VoiceChatService.UseAudioApi is Disabled — there are no "
				.. "AudioDeviceInputs to route, so nobody will hear anybody. Set it to "
				.. "Enabled in Studio (Explorer > VoiceChatService)."
		)
	end

	if defaultVoice == true then
		warn(
			"[VoiceChat] VoiceChatService.EnableDefaultVoice is true — Roblox's "
				.. "proximity voice graph is running alongside this one, so anyone "
				.. "standing near you is heard twice. Set it to false in Studio "
				.. "(Explorer > VoiceChatService)."
		)
	end
end

-- Give the player a microphone, unless something already has.
local function ensureInput(player: Player)
	if not provisioning or player.Parent == nil then
		return
	end
	if player:FindFirstChildOfClass("AudioDeviceInput") then
		return
	end

	local input = Instance.new("AudioDeviceInput")
	input.Name = Constants.INPUT_NAME
	input.Player = player
	-- AccessType/AccessList are left at their defaults (deny-list, empty): no
	-- one is excluded, which is what "everybody hears everybody" means. Narrow
	-- this — never the wiring — if the game ever needs private voice.
	input.Parent = player
end

-- What makes provisioning-by-default safe: if an engine input turns up next to
-- one of ours, ours is the one that goes. It's the one that isn't carrying a
-- voice, and leaving both would have every listener metering a coin flip.
local function dropOurInputIfEngineAdds(player: Player, child: Instance)
	if not child:IsA("AudioDeviceInput") or child.Name == Constants.INPUT_NAME then
		return
	end
	local ours = player:FindFirstChild(Constants.INPUT_NAME)
	if ours ~= nil and ours:IsA("AudioDeviceInput") then
		ours:Destroy()
	end
end

local function watch(player: Player)
	player.ChildAdded:Connect(function(child: Instance)
		dropOurInputIfEngineAdds(player, child)
	end)
	ensureInput(player)
end

function VoiceService.Start()
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	-- Nothing to tear down on leave: the input is parented to the Player, and
	-- that goes with them.

	-- Off the startup path, because resolving the settings takes as long as it
	-- takes and nothing else here should wait on it.
	task.spawn(function()
		local defaultVoice = resolveSetting("EnableDefaultVoice")
		checkConfiguration(defaultVoice)

		provisioning = defaultVoice ~= true
		if not provisioning then
			return
		end
		-- Everyone who joined while the answer was still unknown.
		for _, player in Players:GetPlayers() do
			ensureInput(player)
		end
	end)
end

return VoiceService
