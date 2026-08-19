-- The inactivity card: fires once, when the turn order drops you.
--
-- Its other half — the badge that stays up for as long as you're out — is
-- `TowerSpectatorView`, a separate root. They're still two halves of one answer:
-- the card can be missed (dismissed, or it arrived while the player was looking
-- away, or was never sent because they were already spectating when they joined)
-- and the badge is what makes that survivable. What separated them is *stacking*,
-- not meaning — the card is a question and belongs over everything, the badge is
-- a state and belongs under the HUD it would otherwise cover, and a root's ZIndex
-- is the only thing that can say either. See `TowerSpectatorView`.
--
-- Renders nothing at all when the card is down. It covers the screen to catch
-- clicks, so leaving a transparent copy mounted would quietly swallow every tap
-- on the HUD underneath.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local AfkNotice = require(ReplicatedStorage.Features.TowerGame.AfkNotice)
local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)

-- Client-realm sibling (StarterPlayerScripts.Features.TowerGame).
local TowerAfkController = require(script.Parent.TowerAfkController)

return function()
	local visible, setVisible = React.useState(TowerAfkController.visible)

	React.useEffect(function()
		-- It can change between the first render and this effect, so read once
		-- rather than waiting for a change that may already have happened.
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

	-- The card brings its own full-screen dim and click catcher, so it is the
	-- root — there's nothing left to host now the badge has its own.
	return React.createElement(AfkNotice, {
		missedTurns = TowerAfkController.missedTurns(),
		onDismiss = TowerAfkController.dismiss,
		onResume = TowerAfkController.resume,
		zIndex = Constants.AFK_Z_INDEX,
	})
end
