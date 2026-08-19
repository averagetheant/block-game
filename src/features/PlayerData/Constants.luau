-- Shared config for PlayerData. Read from server (ProfileStore) and client (ReplicatedStorage).
--
-- The profile schema is NOT defined here. Each feature owns its own slice and
-- registers it via a sibling `PlayerData.luau` file — see docs/game/PlayerData.md.

return {
	STORE_NAME = "PlayerData_v1",
	REPLICA_CLASS = "PlayerData",

	-- A testing switch, and `false` is the state to leave it in — that's the one
	-- where player data actually persists.
	--
	-- Turned **on**, nothing loads and nothing saves. Profiles come from
	-- `ProfileStore.Mock` (an in-memory store with no relation to the real
	-- DataStore) and are wiped back to the template after Reconcile, so even a
	-- rejoin inside one server session gets a new player's data rather than the one
	-- the last join left behind.
	--
	-- It exists because a feature gated on a *calendar day* can otherwise be tested
	-- about once a day: claim the daily reward and the run is closed until
	-- tomorrow. Turned on, every play test is day 1 with the reward waiting, which
	-- is also the exact state the join prompt is built for. That's the whole reason
	-- to reach for it, and the reason to put it back afterwards.
	--
	-- The server warns loudly on start while it's on (see `PlayerDataService`),
	-- because the failure mode is silent and expensive: real players in a real
	-- server would each spend a session on data that is thrown away when they
	-- leave. If cash, skins or the first-checkpoint skin ever stop persisting
	-- between sessions, read this line first.
	EPHEMERAL = false,
}
