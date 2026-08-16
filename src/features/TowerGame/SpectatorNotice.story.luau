--!nonstrict
-- UI Labs story for the spectator badge. It takes no data — it's up or it isn't
-- — so the only thing to look at is the thing that actually matters about it:
-- whether two lines of copy still fit the box at every text tier, and whether it
-- reads as a status rather than an alarm.
--
-- `place` moves it around. "top-centre" is where the game puts it, hanging under
-- the HUD's top column; the corners are here because every one of them was tried
-- first and lost to something — see the note on SPECTATOR_NOTICE_WIDTH.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Features = ReplicatedStorage:WaitForChild("Features")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local UILabs = require(ReplicatedStorage.Packages.UILabs)

local TowerGame = require(Features:WaitForChild("TowerGame"))

local MARGIN = TowerGame.Constants.EDGE_MARGIN

local PLACES = {
	["top-centre"] = {
		position = UDim2.new(0.5, 0, 0, TowerGame.Constants.SPECTATOR_NOTICE_TOP),
		anchor = Vector2.new(0.5, 0),
	},
	["top-right"] = { position = UDim2.new(1, -MARGIN, 0, MARGIN), anchor = Vector2.new(1, 0) },
	["top-left"] = { position = UDim2.new(0, MARGIN, 0, MARGIN), anchor = Vector2.new(0, 0) },
	["bottom-right"] = { position = UDim2.new(1, -MARGIN, 1, -MARGIN), anchor = Vector2.new(1, 1) },
	["bottom-left"] = { position = UDim2.new(0, MARGIN, 1, -MARGIN), anchor = Vector2.new(0, 1) },
}

return {
	summary = "The badge that stays up while a player is out of the turn rotation, however they got there. It's the half of the spectator UI that survives being missed — the inactivity card fires once and can be dismissed, this doesn't go away until the player is back in.",
	react = React,
	reactRoblox = ReactRoblox,

	controls = {
		place = UILabs.Choose({ "top-centre", "top-right", "top-left", "bottom-right", "bottom-left" }),
	},

	story = function(props)
		local place = PLACES[props.controls.place] or PLACES["top-centre"]

		return React.createElement(TowerGame.SpectatorNotice, {
			position = place.position,
			anchorPoint = place.anchor,
		})
	end,
}
