local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ProfileStore = require(ServerScriptService.ServerPackages.ProfileStore)
local ReplicaService = require(ReplicatedStorage.Packages.ReplicaService)

-- Requiring PlayerData (the parent init.luau) triggers the auto-discovery loop
-- that pulls every feature's PlayerData.luau slice into the template before
-- we hand it to ProfileStore.
local PlayerData = require(ReplicatedStorage.Features.PlayerData)
local Constants = PlayerData.Constants

local PlayerDataService = {}

-- Runs before any other service that reads player data.
PlayerDataService.Priority = 1

local Store = ProfileStore.New(Constants.STORE_NAME, PlayerData.getTemplate())
local ReplicaToken = ReplicaService.NewClassToken(Constants.REPLICA_CLASS)

local profiles: { [Player]: any } = {}
local replicas: { [Player]: any } = {}

-- Public API -----------------------------------------------------------------

function PlayerDataService.GetData(player: Player): { [string]: any }?
	local profile = profiles[player]
	return if profile then profile.Data else nil
end

function PlayerDataService.GetReplica(player: Player)
	return replicas[player]
end

-- Blessed mutation path. Always route writes through this so:
--   (a) clients receive a Replica diff,
--   (b) ProfileStore autosave persists the change (profile.Data === replica.Data),
--   (c) we get one place to add logging, rate-limiting, or validation later.
function PlayerDataService.SetValue(player: Player, path: { string }, value: any): boolean
	local replica = replicas[player]
	if replica == nil then
		return false
	end
	replica:SetValue(path, value)
	return true
end

-- Lifecycle ------------------------------------------------------------------

-- Start this player's session — from the real store, or from the mock one while
-- `Constants.EPHEMERAL` is on (see the constant for what that's for and when to
-- turn it off).
--
-- `ProfileStore.Mock` takes the key alone: its `StartSessionAsync` doesn't
-- forward the params table, so the `Cancel` callback would be silently dropped
-- rather than honoured. No loss — a mock session loads without yielding on
-- anything, so there is no window for the player to leave inside.
local function startSession(player: Player)
	if Constants.EPHEMERAL then
		return Store.Mock:StartSessionAsync(tostring(player.UserId))
	end
	return Store:StartSessionAsync(tostring(player.UserId), {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})
end

-- Put a mock profile back to the template, in place.
--
-- `Reconcile` only fills in what's *missing*, so a second join inside one server
-- session would otherwise inherit whatever the first one left in the mock store —
-- which for a daily reward means "already claimed", the one state the testing is
-- trying to get out of.
--
-- Cleared and refilled rather than reassigned: `profile.Data` and `replica.Data`
-- have to stay the same table (see the identity check below), and swapping in a
-- fresh one is exactly the drift that check exists to catch.
local function resetToTemplate(profile: any)
	local data = profile.Data
	table.clear(data)
	-- A fresh deep copy per call, so nothing here can alias the template that
	-- every later join is built from.
	for key, value in PlayerData.getTemplate() do
		data[key] = value
	end
end

local function onPlayerAdded(player: Player)
	local profile = startSession(player)

	if profile == nil then
		player:Kick("[PlayerData] couldn't load profile; please rejoin")
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()
	if Constants.EPHEMERAL then
		resetToTemplate(profile)
	end

	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		local replica = replicas[player]
		if replica then
			replica:Destroy()
			replicas[player] = nil
		end
		if player.Parent == Players then
			player:Kick("[PlayerData] profile session ended")
		end
	end)

	-- Invariant: replica.Data and profile.Data must remain the same table.
	-- If someone ever re-assigns profile.Data (or builds a new table and swaps
	-- it in) the replica stops saving silently. Fire a loud warning before
	-- every save so the drift is obvious in the output window.
	profile.OnSave:Connect(function()
		local replica = replicas[player]
		if replica ~= nil and replica.Data ~= profile.Data then
			warn(
				`[PlayerData] identity drift for {player.Name}: `
					.. `replica.Data and profile.Data are no longer the same table. `
					.. `Use PlayerDataService.SetValue / .GetReplica to mutate; `
					.. `do not reassign profile.Data.`
			)
		end
	end)

	if player.Parent ~= Players then
		profile:EndSession()
		return
	end

	profiles[player] = profile
	replicas[player] = ReplicaService.NewReplica({
		ClassToken = ReplicaToken,
		Tags = { UserId = player.UserId },
		Data = profile.Data,
		Replication = player,
	})
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile then
		profile:EndSession()
	end
end

function PlayerDataService.Start()
	if Constants.EPHEMERAL then
		warn(
			"[PlayerData] EPHEMERAL is ON — profiles are mock: nothing loads, nothing saves, "
				.. "and every join starts on the template. Set EPHEMERAL = false in "
				.. "PlayerData/Constants.luau before shipping."
		)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- handle players already in the server (e.g. after a hot reload)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return PlayerDataService
