-- Wires the inactivity card to the controller: shown while the controller says
-- so, and the two buttons call its intents.
--
-- Renders nothing at all when it isn't up. The card covers the screen to catch
-- clicks, so leaving a transparent copy of it mounted would quietly swallow every
-- tap on the HUD underneath.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local AfkNotice = require(ReplicatedStorage.Features.TowerGame.AfkNotice)
local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)

-- Client-realm sibling (StarterPlayerScripts.Features.TowerGame).
local TowerAfkController = require(script.Parent.TowerAfkController)

return function()
	local visible, setVisible = React.useState(TowerAfkController.visible)

	React.useEffect(function()
		-- The packet can land between the first render and this effect, so read
		-- once rather than waiting for a second change that may not come.
		setVisible(TowerAfkController.visible())

		local connection = TowerAfkController.Changed:Connect(function()
			setVisible(TowerAfkController.visible())
		end)
		return function()
			connection:Disconnect()
		end
	end, {})

	if not visible then
		return nil
	end

	return React.createElement(AfkNotice, {
		missedTurns = TowerAfkController.missedTurns(),
		onDismiss = TowerAfkController.dismiss,
		onResume = TowerAfkController.resume,
		zIndex = Constants.AFK_Z_INDEX,
	})
end
