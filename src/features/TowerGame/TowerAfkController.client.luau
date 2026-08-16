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
-- Last seen value of the "Not playing" setting. Kept because what closes the
-- card is the *transition* out of spectating, not the value being false — see
-- the note in Start.
local spectating = false

function TowerAfkController.visible(): boolean
	return visible
end

-- Whether this player is currently out of the turn order, however they got
-- there: benched for inactivity, or their own choice in Settings. The persistent
-- notice reads this; the card is only about the moment they were benched.
function TowerAfkController.spectating(): boolean
	return spectating
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

	spectating = SettingsController.get(Constants.SETTING_NOT_PLAYING) == true

	-- Turning "Not playing" back off anywhere else — the Settings window — answers
	-- the card's question too, so the card closes with it. Settings live in the
	-- profile replica, which is what makes this reach every route into them rather
	-- than only the one the card owns.
	--
	-- What closes it is the **transition** out of spectating, not the setting
	-- merely reading false. That distinction is the whole fix for a card nobody on
	-- a phone could see: the bench arrives over ReplicaService and the card over
	-- ByteNet, two transports with no ordering between them, and `DataChanged`
	-- fires on *any* profile write — cash, which is credited constantly. Test the
	-- level and a payout landing in the gap before the bench replicates closes the
	-- card in the frame it opened. On a desktop in Studio that gap is nothing; on
	-- a phone it's the difference between a popup and a rumour.
	PlayerDataController.DataChanged:Connect(function()
		local now = SettingsController.get(Constants.SETTING_NOT_PLAYING) == true
		local left = spectating and not now
		if now == spectating then
			return
		end
		spectating = now
		if left and visible then
			-- setVisible fires Changed for us.
			setVisible(false)
			return
		end
		-- The notice tracks this too, so a change either way is worth a render.
		TowerAfkController.Changed:Fire()
	end)
end

return TowerAfkController
