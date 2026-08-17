-- Persistent stats for TowerGame, and the leaderboard that shows them.
--
-- Two jobs, deliberately split out of TowerService: own the profile slice
-- registered in PlayerData.luau, and mirror it into a `leaderstats` folder so
-- Roblox renders it on the player list. TowerService calls in on the two events
-- that matter (a piece was dropped, the tower set a record) and knows nothing
-- about ProfileStore.
--
-- Every write goes through PlayerDataService.SetValue — the blessed path that
-- fires a replica diff AND lands in the next autosave. The leaderstats values
-- are display mirrors; the profile is the truth.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)
local PlayerDataService = require(ServerScriptService.Features.PlayerData.PlayerDataService)

local TowerStatsService = {}

-- After PlayerData (1), before TowerService (20) so the leaderstats folder
-- exists by the time a piece can be dropped.
TowerStatsService.Priority = 15

local KEY = Constants.PROFILE_KEY

-- How long to wait for a profile to load before giving up on syncing the
-- leaderboard for that player (they keep playing; only the display is stale).
local PROFILE_WAIT_SECONDS = 30

local stats: { [Player]: { blocks: IntValue, height: IntValue } } = {}

local function slice(player: Player): { [string]: any }?
	local data = PlayerDataService.GetData(player)
	return if data then data[KEY] else nil
end

local function ensureFolder(player: Player)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"

	local blocks = Instance.new("IntValue")
	blocks.Name = Constants.STAT_BLOCKS
	blocks.Parent = folder

	local height = Instance.new("IntValue")
	height.Name = Constants.STAT_HEIGHT
	height.Parent = folder

	folder.Parent = player
	stats[player] = { blocks = blocks, height = height }

	-- The profile loads asynchronously, so show zeroes now and backfill the real
	-- values when the session lands.
	task.spawn(function()
		local deadline = os.clock() + PROFILE_WAIT_SECONDS
		while slice(player) == nil and os.clock() < deadline and player.Parent == Players do
			task.wait(0.25)
		end

		local saved = slice(player)
		if saved == nil or player.Parent ~= Players then
			return
		end
		blocks.Value = saved.BlocksPlaced or 0
		-- The leaderboard column is an integer; the profile keeps the decimals.
		height.Value = math.floor(saved.BiggestHeight or 0)
	end)
end

-- Called once per piece the player actually drops (including auto-drops — the
-- clock running out still placed their block).
function TowerStatsService.recordBlockPlaced(player: Player)
	local saved = slice(player)
	if saved == nil then
		return
	end

	local total = (saved.BlocksPlaced or 0) + 1
	PlayerDataService.SetValue(player, { KEY, "BlocksPlaced" }, total)

	local entry = stats[player]
	if entry then
		entry.blocks.Value = total
	end
end

-- One player's own best. Nothing happens unless it beats what's on the profile,
-- so this is safe to call with whatever a tower currently measures.
function TowerStatsService.recordPlayerHeight(player: Player, height: number)
	local saved = slice(player)
	if saved == nil or height <= (saved.BiggestHeight or 0) then
		return
	end

	PlayerDataService.SetValue(player, { KEY, "BiggestHeight" }, height)

	local entry = stats[player]
	if entry then
		entry.height.Value = math.floor(height)
	end
end

-- The tower hit a new record. It's one shared tower, so this is a record for
-- everyone currently in the server, not just whoever placed the last piece.
--
-- PVP is the other case and calls `recordPlayerHeight` directly: there the tower
-- is one player's, so crediting the room would hand five people a record they
-- didn't build.
function TowerStatsService.recordHeight(height: number)
	for _, player in Players:GetPlayers() do
		TowerStatsService.recordPlayerHeight(player, height)
	end
end

-- Remember that the "Not playing" setting was turned on *for* this player by the
-- inactivity check rather than by them. See the note on `AutoAfk` in
-- PlayerData.luau for why that distinction has to survive the session.
--
-- Not a stat, but the profile slice is this module's to touch: PlayerData.luau
-- registers the shape and everything that reads or writes it comes through here.
function TowerStatsService.setAutoAfk(player: Player, value: boolean)
	if slice(player) == nil then
		return
	end
	PlayerDataService.SetValue(player, { KEY, "AutoAfk" }, value)
end

-- Whether this player was benched by the inactivity check last time, clearing
-- the flag as it answers. **Yields**: the profile loads asynchronously and the
-- caller runs on join, so a plain read would answer "no" for every player every
-- time — which is the bug this whole flag exists to avoid, arrived at from the
-- other direction. A profile that never loads answers false and stays as it is.
function TowerStatsService.consumeAutoAfk(player: Player): boolean
	local deadline = os.clock() + PROFILE_WAIT_SECONDS
	while slice(player) == nil and os.clock() < deadline and player.Parent == Players do
		task.wait(0.25)
	end

	local saved = slice(player)
	if saved == nil or saved.AutoAfk ~= true then
		return false
	end
	PlayerDataService.SetValue(player, { KEY, "AutoAfk" }, false)
	return true
end

-- Whether the checkpoint about to clear would be this player's first, i.e.
-- whether they still qualify for the first-checkpoint quest.
--
-- A profile that hasn't loaded answers **false**, not "maybe": the caller uses
-- this to decide whether to hand over the quest prize, and a grant written
-- against a missing profile is one that fails anyway — better to leave the flag
-- alone and let them earn it on the next floor than to burn the once-ever moment
-- on a write that goes nowhere.
function TowerStatsService.isFirstCheckpointFor(player: Player): boolean
	local saved = slice(player)
	return saved ~= nil and not saved.SeenCheckpoint
end

-- A checkpoint just cleared. Credits everyone in the server for the same reason
-- `recordHeight` does — it's one shared tower, so it's one shared moment — and
-- it's what retires the HUD's first-checkpoint quest (see TowerHUD).
--
-- Called by CheckpointQuestService *after* it has handed the prize over: this
-- flag is what the quest reads to know who still qualifies, so flipping it first
-- would close the quest on the very player it was about to pay.
--
-- Write-once: this only ever goes false → true, so the common case (a veteran on
-- their tenth floor) skips the SetValue and the replica diff it would fire.
function TowerStatsService.recordCheckpointSeen()
	for _, player in Players:GetPlayers() do
		local saved = slice(player)
		if saved == nil or saved.SeenCheckpoint then
			continue
		end
		PlayerDataService.SetValue(player, { KEY, "SeenCheckpoint" }, true)
	end
end

function TowerStatsService.Start()
	Players.PlayerAdded:Connect(ensureFolder)
	Players.PlayerRemoving:Connect(function(player)
		stats[player] = nil
	end)

	for _, player in Players:GetPlayers() do
		ensureFolder(player)
	end
end

return TowerStatsService
