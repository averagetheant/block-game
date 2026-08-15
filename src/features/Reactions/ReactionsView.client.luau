-- Wires the bar and the float layer to live data: the bar's contents come off
-- the PlayerData replica, and every reaction anyone sends arrives on the
-- controller's Played signal.
--
-- The bar rides inside HideWhenFrameOpen so opening the shop slides it away
-- with the rest of the HUD. The float layer deliberately doesn't — a reaction
-- already in flight shouldn't lurch off the side of the screen because
-- someone opened a window mid-flight.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Features = ReplicatedStorage:WaitForChild("Features")

local React = require(ReplicatedStorage.Packages.React)
local Boil = require(ReplicatedStorage.Shared.Boil)
local UIShell = require(Features:WaitForChild("UIShell"))

local ReactionBar = require(ReplicatedStorage.Features.Reactions.ReactionBar)
local ReactionFloat = require(ReplicatedStorage.Features.Reactions.ReactionFloat)

-- Client-realm siblings (StarterPlayerScripts.Features tree).
local ReactionsController = require(script.Parent.ReactionsController)
local PlayerDataController = require(script.Parent.Parent.PlayerData.PlayerDataController)

-- Whether the bar starts open. On a PC the column costs a strip of screen edge
-- nobody is otherwise using, so showing it saves a click; on a phone that strip
-- is scarce and the buttons sit right where the thumb already rests, so touch
-- keeps the pull-in tab. Keyboard wins when a machine reports several (a laptop
-- with a touchscreen, Studio emulation) — same call TowerView's control hint
-- makes, for the same reason: it's what the player is most likely holding.
local function openOnMount(): boolean
	return UserInputService.KeyboardEnabled
end

return function()
	-- Subscribed for the re-render; the controller is what turns the stored
	-- list into exactly SLOT_COUNT valid ids.
	Boil.useReplica(PlayerDataController, "Reactions")
	local slots = ReactionsController.slots()

	-- Decided once, on mount. `KeyboardEnabled` can flip mid-session (a keyboard
	-- paired to a tablet), and re-answering would hand the bar a fresh mount
	-- position while the player is in the middle of using it.
	local initialOpen: boolean = React.useState(openOnMount)

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
			-- Slides out the way the bar already travels. Hiding it downward
			-- would send a right-edge column diagonally off the corner.
			direction = "right",
			basePosition = UDim2.fromScale(0, 0),
			anchorPoint = Vector2.new(0, 0),
			size = UDim2.fromScale(1, 1),
		}, {
			Bar = React.createElement(ReactionBar, {
				slots = slots,
				onSend = ReactionsController.send,
				initialOpen = initialOpen,
			}),
		}),

		Floats = React.createElement(ReactionFloat, {
			played = ReactionsController.Played,
		}),
	})
end
