-- Client core for the inactivity card: holds whether it's up, and owns the two
-- things the player can do about it.
--
-- Headless (see docs/game/headless-core.md) — it draws nothing. AfkNotice is the
-- card; TowerAfkView wires this to it.
--
-- The server has already taken them out of the rotation by the time the packet
-- lands, so nothing here decides anything. "I'm here!" is the ordinary Settings
-- write every other toggle uses, which is what makes the card and the Settings
-- window agree without either knowing about the other.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Packages.Signal)
local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)
local Packets = require(ReplicatedStorage.Features.TowerGame.Packets)

-- Client-realm siblings from other features (StarterPlayerScripts.Features).
local SettingsController = require(script.Parent.Parent.Settings.SettingsController)
local PlayerDataController = require(script.Parent.Parent.PlayerData.PlayerDataController)

local TowerAfkController = {}

-- After the controllers whose state it reads.
TowerAfkController.Priority = 40

-- Fires when the card should appear or disappear.
TowerAfkController.Changed = Signal.new()

local visible = false
-- How many turns went by, for the card's own wording. The server counts them;
-- the client only repeats the number.
local missedTurns = 0

function TowerAfkController.visible(): boolean
	return visible
end

function TowerAfkController.missedTurns(): number
	return missedTurns
end

local function setVisible(next: boolean)
	if visible == next then
		return
	end
	visible = next
	TowerAfkController.Changed:Fire()
end

-- "OK" — they've read it. The card goes; they stay out of the rotation until
-- they say otherwise, here or in the Settings window.
function TowerAfkController.dismiss()
	setVisible(false)
end

-- "I'm here!" — put them back in.
function TowerAfkController.resume()
	setVisible(false)
	SettingsController.setToggle(Constants.SETTING_NOT_PLAYING, false)
end

function TowerAfkController.Start()
	Packets.AfkNotice.listen(function(payload)
		missedTurns = payload.turns
		setVisible(true)
	end)

	-- Turning "Not playing" back off anywhere else — the Settings window — answers
	-- the card's question too. Leaving it up would be asking a player who has
	-- already come back whether they're still there. Settings live in the profile
	-- replica, so this is the change that reaches every route into them rather
	-- than only the one the card owns.
	PlayerDataController.DataChanged:Connect(function()
		if visible and SettingsController.get(Constants.SETTING_NOT_PLAYING) ~= true then
			setVisible(false)
		end
	end)
end

return TowerAfkController
