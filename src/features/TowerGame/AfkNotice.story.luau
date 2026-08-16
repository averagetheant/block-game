--!nonstrict
-- UI Labs story for the inactivity card. Both buttons print instead of writing a
-- setting — there's no server here, and the point of the story is the card, not
-- the rule behind it.
--
-- The thing worth checking here is the copy at both text tiers: the title wraps
-- to two lines at this width and the card's height is computed from the ladder
-- rather than measured, so a longer sentence or a bigger tier is exactly what
-- would clip. Drive `missedTurns` to see the detail line reword itself.
--
-- The card covers whatever it's mounted in, so in Labs it fills the preview pane
-- the way it fills the screen in game.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Features = ReplicatedStorage:WaitForChild("Features")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local UILabs = require(ReplicatedStorage.Packages.UILabs)

local TowerGame = require(Features:WaitForChild("TowerGame"))

return {
	summary = "The card a player gets when the turn order drops them for sitting out two turns running. Red closes it and leaves them spectating; green puts them back in the rotation. It's centred and covers the screen because the player it's for is, by definition, not looking at the corners.",
	react = React,
	reactRoblox = ReactRoblox,

	controls = {
		missedTurns = UILabs.Slider(2, 1, 6, 1),
	},

	story = function(props)
		return React.createElement(TowerGame.AfkNotice, {
			missedTurns = props.controls.missedTurns,
			onDismiss = function()
				print("[TowerGame] AFK card dismissed")
			end,
			onResume = function()
				print("[TowerGame] back in the rotation")
			end,
		})
	end,
}
