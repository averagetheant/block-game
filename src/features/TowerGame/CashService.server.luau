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

local CashService = {}

-- After PlayerData (1), alongside the other TowerGame services.
CashService.Priority = 15

local KEY = Constants.PROFILE_KEY

local function slice(player: Player): { [string]: any }?
	local data = PlayerDataService.GetData(player)
	return if data then data[KEY] else nil
end

-- The one write path. Returns quietly for a player whose profile hasn't loaded
-- yet — they'll earn on the next award rather than banking onto a nil.
function CashService.award(player: Player, amount: number)
	local saved = slice(player)
	if saved == nil or amount <= 0 then
		return
	end
	PlayerDataService.SetValue(player, { KEY, "Cash" }, (saved.Cash or 0) + amount)
end

function CashService.awardAll(amount: number)
	for _, player in Players:GetPlayers() do
		CashService.award(player, amount)
	end
end

-- Called by TowerService when a checkpoint pushes the run into a new zone.
function CashService.awardZone()
	CashService.awardAll(Constants.CASH_PER_ZONE)
end

function CashService.Start()
	-- Paid on a wall clock rather than per-player join time: everyone in the
	-- server gets the same tick at the same moment, which keeps the flying-cash
	-- animation a shared moment instead of a private one.
	task.spawn(function()
		while true do
			task.wait(Constants.CASH_INTERVAL_SECONDS)
			CashService.awardAll(Constants.CASH_PER_INTERVAL)
		end
	end)
end

return CashService
