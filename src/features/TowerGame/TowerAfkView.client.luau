-- Wires the two spectator surfaces to the controller: the card that fires once
-- when the turn order drops you, and the badge that stays up for as long as
-- you're out.
--
-- Both live here rather than in separate presentations because they're two
-- halves of one answer. The card can be missed — dismissed, or arrived while the
-- player was looking away, or never sent because they were already spectating
-- when they joined — and the badge is what makes that survivable: the state is
-- always legible even when the moment wasn't.
--
-- Renders nothing at all when neither applies. The card covers the screen to
-- catch clicks, so leaving a transparent copy mounted would quietly swallow
-- every tap on the HUD underneath.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ui = require(ReplicatedStorage.Shared.Boil).ui
local AfkNotice = require(ReplicatedStorage.Features.TowerGame.AfkNotice)
local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)
local SpectatorNotice = require(ReplicatedStorage.Features.TowerGame.SpectatorNotice)

-- Client-realm sibling (StarterPlayerScripts.Features.TowerGame).
local TowerAfkController = require(script.Parent.TowerAfkController)

type State = {
	card: boolean,
	spectating: boolean,
}

local function read(): State
	return {
		card = TowerAfkController.visible(),
		spectating = TowerAfkController.spectating(),
	}
end

return function()
	local state, setState = React.useState(read)
	-- The badge is the one thing here pinned to the top edge, and the top edge is
	-- contested: the root ScreenGui ignores the GUI inset, so canvas y = 0 is the
	-- true top of the display and Roblox's own topbar — the player-list button
	-- among it — occupies the first ~36 screen pixels of this corner.
	--
	-- The inset is measured in *screen* pixels and everything in here is in canvas
	-- units, so it has to be divided by the viewport scale to mean the same
	-- distance (ScaleLayer documents this conversion). A plain constant can't:
	-- whatever clears the topbar on a monitor is half that on a phone at the 0.5
	-- scale floor, which is the device that reported not seeing this at all.
	local viewportScale = ui.useViewportScale()
	local topInset = GuiService:GetGuiInset().Y / math.max(viewportScale, 0.05)

	React.useEffect(function()
		-- Either can change between the first render and this effect, so read
		-- once rather than waiting for a change that may already have happened.
		setState(read())

		local connection = TowerAfkController.Changed:Connect(function()
			setState(read())
		end)
		return function()
			connection:Disconnect()
		end
	end, {})

	if not state.card and not state.spectating then
		return nil
	end

	local children: { [string]: any } = {}

	if state.spectating then
		children.Notice = React.createElement(SpectatorNotice, {
			position = UDim2.new(0.5, 0, 0, topInset + Constants.SPECTATOR_NOTICE_TOP),
			anchorPoint = Vector2.new(0.5, 0),
			zIndex = 1,
		})
	end

	if state.card then
		-- Above the badge: the card dims the screen, and a badge punching through
		-- its own dimming would look like a bug rather than a layer.
		children.Card = React.createElement(AfkNotice, {
			missedTurns = TowerAfkController.missedTurns(),
			onDismiss = TowerAfkController.dismiss,
			onResume = TowerAfkController.resume,
			zIndex = 2,
		})
	end

	-- A transparent host so the two can be layered against each other. Not
	-- `Active`: only the card is meant to eat input, and it brings its own
	-- full-screen catcher.
	return React.createElement("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = Constants.AFK_Z_INDEX,
	}, children)
end
