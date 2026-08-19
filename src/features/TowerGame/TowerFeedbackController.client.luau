-- Local feedback: the cues that belong to *this* player rather than to the
-- world. The turn chime, and the cash payout that the HUD animates.
--
-- Cash deliberately has no packet. It's persisted on the profile, so the replica
-- diff is the event — this watches the value and turns an increase into a sound
-- plus a signal. One source of truth, no way for the counter and the animation
-- to disagree about how much arrived.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Packages.Signal)

local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)
local Sfx = require(ReplicatedStorage.Features.TowerGame.Sfx)

-- Client-realm siblings (StarterPlayerScripts.Features.*).
local PlayerDataController = require(script.Parent.Parent.PlayerData.PlayerDataController)
local TowerController = require(script.Parent.TowerController)

local TowerFeedbackController = {}

-- Fires with the amount gained whenever this player's cash goes up.
TowerFeedbackController.CashAwarded = Signal.new()

local function cashOf(data: any): number?
	local slice = if data then data[Constants.PROFILE_KEY] else nil
	return if slice then slice.Cash or 0 else nil
end

function TowerFeedbackController.Start()
	-- Warm the cue library before the first block lands. Every per-material impact
	-- take is its own asset, and an unloaded one-shot plays after it downloads —
	-- i.e. after the landing it belongs to. Spawned because it yields on the
	-- network, and this is the file that owns "sounds this player hears".
	task.spawn(Sfx.preload)

	local wasMyTurn = false
	TowerController.DataChanged:Connect(function()
		local isMyTurn = TowerController.isMyTurn()
		if isMyTurn and not wasMyTurn then
			Sfx.play("YourTurn")
		end
		wasMyTurn = isMyTurn
	end)

	-- nil until the profile lands; the first real value is a baseline, not a win.
	local lastCash: number? = cashOf(PlayerDataController.GetData())

	PlayerDataController.DataChanged:Connect(function(data)
		local cash = cashOf(data)
		if cash == nil then
			return
		end
		local previous = lastCash
		lastCash = cash
		if previous == nil or cash <= previous then
			return
		end

		Sfx.play("CashSound")
		TowerFeedbackController.CashAwarded:Fire(cash - previous)
	end)
end

return TowerFeedbackController
