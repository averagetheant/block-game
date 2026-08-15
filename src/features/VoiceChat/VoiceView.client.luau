-- Wires the speaker chips to live voice: the controller says who is talking,
-- this puts them in the bottom-left corner.
--
-- Re-renders only when the *set* of speakers changes, because that's the only
-- thing the controller's signal fires on. The per-speaker level is handed down
-- as a getter instead — the chips read it every frame for their rings without
-- any of it going through React.
--
-- Deliberately not inside HideWhenFrameOpen: opening the shop doesn't stop
-- people talking, and losing the one indicator that says who is talking because
-- a window is up is worse than the overlap.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Constants = require(ReplicatedStorage.Features.VoiceChat.Constants)
local SpeakerList = require(ReplicatedStorage.Features.VoiceChat.SpeakerList)

-- Client-realm sibling (StarterPlayerScripts.Features.VoiceChat.VoiceController).
local VoiceController = require(script.Parent.VoiceController)

return function()
	local speakers, setSpeakers = React.useState(VoiceController.speakers)

	React.useEffect(function()
		-- Between the first render and this effect someone may have started
		-- talking; read once so that isn't missed until the next change.
		setSpeakers(VoiceController.speakers())

		local connection = VoiceController.Changed:Connect(function()
			setSpeakers(VoiceController.speakers())
		end)
		return function()
			connection:Disconnect()
		end
	end, {})

	return React.createElement(SpeakerList, {
		speakers = speakers,
		levelOf = VoiceController.levelOf,
		position = UDim2.new(0, Constants.EDGE_MARGIN, 1, -Constants.BOTTOM_OFFSET),
		-- Pinned by its bottom-left corner, so the column grows up the left edge
		-- as more people talk instead of moving the first chip.
		anchorPoint = Vector2.new(0, 1),
		zIndex = Constants.Z_INDEX,
	})
end
