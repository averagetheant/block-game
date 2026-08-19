--!nonstrict
-- UI Labs story for the vote screen. Drives the real component with the same
-- props the view feeds it in game, so what you tune here is what ships.
--
-- The ballot is the *real* registry: requiring the feature runs its discovery
-- pass, so whatever gamemodes the game's features registered are the panels you
-- see. With none registered the story is empty — which is exactly what the
-- screen does in game.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local UILabs = require(ReplicatedStorage.Packages.UILabs)

local GamemodeVote = require(ReplicatedStorage.Features.GamemodeVote)

-- Stand-in voters. The first accounts ever created, so the headshots resolve.
local CROWD = { 1, 2, 3, 4, 5, 6 }

return {
	summary = "The gamemode vote. Hover a panel to see it lift, click to drop your headshot on it, and click the same one again to re-stamp it — a vote moves but is never taken back. crowdVotes deals stand-ins across the ballot, winnerIndex shows the resolved state (which locks the panels and drops the hover with them).",
	react = React,
	reactRoblox = ReactRoblox,

	controls = {
		crowdVotes = UILabs.Slider(4, 0, #CROWD, 1),
		secondsLeft = UILabs.Slider(9, 0, 60, 1),
		-- Gives the first stand-in the 2x Votes gamepass, so the tag on a
		-- weighted stamp can be eyeballed against the plain ones next to it.
		weightedVoter = false,
		-- 0 = still voting. Anything else resolves the poll on that panel, which
		-- locks the clicks and fades the others.
		winnerIndex = UILabs.Slider(0, 0, 6, 1),
	},

	story = function(props)
		local c = props.controls
		local options = GamemodeVote.list()
		local myVote, setMyVote = React.useState(nil :: string?)
		-- The press count the server keeps per voter. Kept here too, because the
		-- behaviour worth checking in this story is the one with no other tell:
		-- clicking the panel you already hold doesn't take the vote back, doesn't
		-- move the headshot, and doesn't change anything else on screen — it just
		-- lands the stamp again. Click a panel twice and watch for the slam.
		local myStamps, setMyStamps = React.useState(0)

		-- Deal the stand-ins round-robin so every panel has someone on it to
		-- eyeball, then add your own click on top.
		local votersByOption: { [string]: { number } } = {}
		for _, option in options do
			votersByOption[option.id] = {}
		end
		if #options > 0 then
			for index = 1, c.crowdVotes do
				local option = options[(index - 1) % #options + 1]
				table.insert(votersByOption[option.id], CROWD[index])
			end
			if myVote ~= nil and votersByOption[myVote] then
				-- 0 stands in for the local player, whose headshot UI Labs can't
				-- resolve without a running game.
				table.insert(votersByOption[myVote], 0)
			end
		end

		local winner = options[c.winnerIndex]

		local voteWeights = if c.weightedVoter then { [CROWD[1]] = 2 } else {}

		return React.createElement(GamemodeVote.UI, {
			options = options,
			votersByOption = votersByOption,
			voteWeights = voteWeights,
			-- Only the local stand-in re-stamps here; the crowd is static.
			voteStamps = { [0] = myStamps },
			secondsLeft = c.secondsLeft,
			winnerId = if winner then winner.id else nil,
			onVote = function(optionId: string)
				-- Exactly what the server does: the press always lands on the panel
				-- pressed, and every press counts as a fresh stamp.
				setMyVote(optionId)
				setMyStamps(function(previous)
					return previous + 1
				end)
			end,
		})
	end,
}
