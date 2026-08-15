--!nonstrict
-- UI Labs story for the speaker column. There's no voice in Labs, so the
-- speakers are fakes and the microphone is a slider: drive `level` and every
-- ring swells together, which is the one thing about this UI that can't be
-- judged from a still.
--
-- Push `speaking` past MAX_SHOWN to see the column stop growing and report the
-- rest as a count instead — the case a hundred-player server actually hits.
--
-- The column anchors to the bottom-left of whatever it's mounted in, so here it
-- sits in the corner of the preview pane rather than the screen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Features = ReplicatedStorage:WaitForChild("Features")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local UILabs = require(ReplicatedStorage.Packages.UILabs)

local VoiceChat = require(Features:WaitForChild("VoiceChat"))

-- Real user ids, so the headshots resolve to real avatars. The names are the
-- interesting part: the last one is past NAME_MAX_CHARS and shows the cut.
local CROWD = {
	{ userId = 1, displayName = "Roblox" },
	{ userId = 156, displayName = "builderman" },
	{ userId = 261, displayName = "Shedletsky" },
	{ userId = 16, displayName = "Matt Dusek" },
	{ userId = 2, displayName = "AVeryLongDisplayName" },
	{ userId = 3, displayName = "Corner Case" },
}

return {
	summary = "Who's talking, bottom-left. One chip per live speaker — headshot, display name, and a ring that swells with their microphone. `level` drives every ring at once; `speaking` past 4 (MAX_SHOWN) trims the column to the most recent talkers and counts the rest underneath.",
	react = React,
	reactRoblox = ReactRoblox,

	controls = {
		speaking = UILabs.Slider(3, 0, #CROWD, 1),
		level = UILabs.Slider(0.45, 0, 1, 0.05),
	},

	story = function(props)
		local c = props.controls

		local speakers = {}
		for index = 1, c.speaking do
			table.insert(speakers, CROWD[index])
		end

		return React.createElement(VoiceChat.SpeakerList, {
			speakers = speakers,
			levelOf = function()
				return c.level
			end,
			position = UDim2.new(0, VoiceChat.Constants.EDGE_MARGIN, 1, -VoiceChat.Constants.EDGE_MARGIN),
			anchorPoint = Vector2.new(0, 1),
		})
	end,
}
