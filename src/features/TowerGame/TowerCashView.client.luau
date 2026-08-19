-- The money readout, mounted as its own root rather than as a piece of each HUD.
--
-- It used to live inside both HUDs, which put it on the same layer as the rest of
-- the game — under every window in the experience. That is fine for the number
-- and fatal for the bills: `CashFly` bursts from the middle of the screen, which
-- is exactly where an open window is, so a payout that landed while the daily
-- rewards window (or the shop, or the inventory) was up played out entirely
-- behind it. The one moment a player most wants to see coins arrive is the moment
-- they claimed something.
--
-- So it sits on `ui.layers.flourish`: above every window, because a reward
-- landing is the game answering something the player just did, and that answer
-- shouldn't be filed behind the thing they did it in.
--
-- Always mounted, which is also a fix: the two HUDs each render `nil` in the
-- other's mode, and the counter's continuity across a round break is not
-- something either of them should own.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Boil = require(ReplicatedStorage.Shared.Boil)
local ui = Boil.ui

local CashCounter = require(ReplicatedStorage.Features.TowerGame.CashCounter)
local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)

-- Client-realm siblings.
local PlayerDataController = require(script.Parent.Parent.PlayerData.PlayerDataController)
local TowerFeedbackController = require(script.Parent.TowerFeedbackController)

return function()
	local profile = Boil.useReplica(PlayerDataController, Constants.PROFILE_KEY)

	-- A transparent full-screen slot carrying the layer. The counter pins itself
	-- to its own corner and the bills start in the middle of the screen, so what
	-- this wraps is a region rather than a widget.
	return React.createElement(ui.Slot, {
		name = "TowerCash",
		size = UDim2.fromScale(1, 1),
		zIndex = ui.layers.flourish,
	}, {
		Counter = React.createElement(CashCounter, {
			cash = if profile then profile.Cash or 0 else 0,
			-- The replica diff is the event (see TowerFeedbackController): one
			-- source of truth, so the number and the animation can't disagree
			-- about how much arrived.
			awarded = TowerFeedbackController.CashAwarded,
		}),
	})
end
