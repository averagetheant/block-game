-- Wires the bar and the float layer to live data: the bar's contents come off
-- the PlayerData replica, and every reaction anyone sends arrives on the
-- controller's Played signal.
--
-- The bar rides inside HideWhenFrameOpen so opening the shop slides it away
-- with the rest of the HUD. The float layer deliberately doesn't — a reaction
-- already in flight shouldn't lurch off the bottom of the screen because
-- someone opened a window mid-flight.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Features = ReplicatedStorage:WaitForChild("Features")

local React = require(ReplicatedStorage.Packages.React)
local Boil = require(ReplicatedStorage.Shared.Boil)
local UIShell = require(Features:WaitForChild("UIShell"))

local ReactionBar = require(ReplicatedStorage.Features.Reactions.ReactionBar)
local ReactionFloat = require(ReplicatedStorage.Features.Reactions.ReactionFloat)

-- Client-realm siblings (StarterPlayerScripts.Features tree).
local ReactionsController = require(script.Parent.ReactionsController)
local PlayerDataController = require(script.Parent.Parent.PlayerData.PlayerDataController)

return function()
	-- Subscribed for the re-render; the controller is what turns the stored
	-- list into exactly SLOT_COUNT valid ids.
	Boil.useReplica(PlayerDataController, "Reactions")
	local slots = ReactionsController.slots()

	-- Above the game HUD: the bar's open state overlaps whatever a HUD keeps at
	-- the bottom of the screen, and a reaction in flight should pass in front of
	-- the HUD rather than behind it.
	return React.createElement("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, {
		BarLayer = React.createElement(UIShell.HideWhenFrameOpen, {
			direction = "bottom",
			basePosition = UDim2.fromScale(0, 0),
			anchorPoint = Vector2.new(0, 0),
			size = UDim2.fromScale(1, 1),
		}, {
			Bar = React.createElement(ReactionBar, {
				slots = slots,
				onSend = ReactionsController.send,
			}),
		}),

		Floats = React.createElement(ReactionFloat, {
			played = ReactionsController.Played,
		}),
	})
end
