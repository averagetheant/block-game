-- Cash: earned by pushing the tower into new zones, and by simply sticking
-- around.
--
-- Both awards go to *everyone in the server*, because both are things the room
-- did together — one tower, one clock. There's no packet here: cash lives on the
-- profile, so the replica diff is what tells a client it got paid, and the HUD
-- animates off the value going up.
--
-- Every write goes through PlayerDataService.SetValue, the blessed path that
-- lands in the replica and the next autosave.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)
local PlayerDataService = require(ServerScriptService.Features.PlayerData.PlayerDataService)
local StoreService = require(ServerScriptService.Features.Store.StoreService)

-- Every coin the game pays out passes through `award`, which makes this the one
-- place the economy's source side can be measured. See docs/game/Analytics.md.
local AnalyticsService = require(ServerScriptService.Features.Analytics.AnalyticsService)
local AnalyticsConstants = require(ReplicatedStorage.Features.Analytics.Constants)

local CashService = {}

-- After PlayerData (1), alongside the other TowerGame services.
CashService.Priority = 15

local KEY = Constants.PROFILE_KEY

local function slice(player: Player): { [string]: any }?
	local data = PlayerDataService.GetData(player)
	return if data then data[KEY] else nil
end

-- What the 2x Cash gamepass multiplies this player's earnings by.
--
-- It hangs off the single write path below rather than off each award site, so
-- every way the game pays — zones, height, the clock, and anything a later
-- feature adds — is doubled by the same rule. Coins bought with Robux are a
-- purchase rather than earnings and are granted by StoreService, which never
-- comes through here.
local function multiplierFor(player: Player): number
	if StoreService.ownsGamepass(player, Constants.GAMEPASSES.DOUBLE_CASH) then
		return Constants.DOUBLE_CASH_MULTIPLIER
	end
	return 1
end

-- The one write path. Returns quietly for a player whose profile hasn't loaded
-- yet — they'll earn on the next award rather than banking onto a nil.
--
-- `source` names which tap paid out. It exists for the analytics event rather
-- than for the write — coins are coins whatever earned them — but "the earn
-- curve is too fast" is unanswerable without knowing which tap it's running
-- from, and that question decides what the Robux bundles can be priced at.
--
-- Roblox counts unique SKUs per experience (100 of them), so these stay a
-- handful of literals: never a player name, a round number, or anything else
-- that grows.
function CashService.award(player: Player, amount: number, source: string?)
	local saved = slice(player)
	if saved == nil or amount <= 0 then
		return
	end
	-- Floored, so a multiplier can never mint a fraction of a coin.
	local paid = math.floor(amount * multiplierFor(player))
	local balance = (saved.Cash or 0) + paid
	PlayerDataService.SetValue(player, { KEY, "Cash" }, balance)

	-- The *paid* amount, after the gamepass multiplier: the dashboard should
	-- show what actually entered the economy, not what it would have been
	-- without the pass. `endingBalance` is Roblox's ask and is why this sits
	-- after the write rather than before it.
	AnalyticsService.economy(
		player,
		"source",
		paid,
		balance,
		AnalyticsConstants.TRANSACTION.GAMEPLAY,
		source or "Unknown"
	)
end

function CashService.awardAll(amount: number, source: string?)
	for _, player in Players:GetPlayers() do
		CashService.award(player, amount, source)
	end
end

-- Called by TowerService when a checkpoint pushes the run into a new zone.
function CashService.awardZone()
	CashService.awardAll(Constants.CASH_PER_ZONE, "Zone")
end

function CashService.Start()
	-- Paid on a wall clock rather than per-player join time: everyone in the
	-- server gets the same tick at the same moment, which keeps the flying-cash
	-- animation a shared moment instead of a private one.
	task.spawn(function()
		while true do
			task.wait(Constants.CASH_INTERVAL_SECONDS)
			CashService.awardAll(Constants.CASH_PER_INTERVAL, "Idle")
		end
	end)
end

return CashService
