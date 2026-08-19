--!strict
-- The first-checkpoint quest line: a six-second notification under the storm
-- clock, shown to a player who has never been in the server when a checkpoint
-- cleared.
--
-- It exists because reaching the first checkpoint is where most new players stop
-- playing, and the climb up to it used to promise nothing they could picture.
-- This names a prize they can't get any other way, and then hands it over in
-- place — the line doesn't vanish on the clear, it flips to `claimed` for a few
-- seconds so the payoff lands where the promise was made.
--
-- **A bare label, not a panel.** It's one more line in a stack of lines that all
-- describe the same climb (distance on the progress line, deadline on the clock,
-- value here), and a surface around it made it read as a separate widget parked
-- on top of the HUD rather than as part of that block. Colour carries the whole
-- distinction: gold while it's a promise, green once it's paid.
--
-- Dumb by construction: two strings and a boolean. Who qualifies, how long it
-- stays up, when it's claimed and what the prize actually is are all decided
-- elsewhere (`TowerView.useCheckpointQuest` reads the profile flag and runs both
-- clocks, CheckpointQuestService does the granting).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ui = require(ReplicatedStorage.Shared.Boil).ui

-- Same tier as the storm countdown above it: a call to action read at a glance
-- mid-round holds the body floor. The row is sized from the text so bumping the
-- tier can't crop a descender.
local TEXT_SIZE = ui.theme.textSizeRegular
local LINE_HEIGHT = TEXT_SIZE + 8

-- Gold to read as "this is worth something" rather than as another status line,
-- and the kit's green once it's been paid — the same green the turn dial uses for
-- "you're fine".
local PROMISE_COLOR = Color3.fromRGB(255, 214, 112)
local CLAIMED_COLOR = Color3.fromRGB(122, 226, 132)

export type Props = {
	-- The prize's display name, used only once it's been handed over. The
	-- unclaimed line deliberately doesn't name it: "a RARE skin" is a better hook
	-- than a noun, and it leaves the reveal somewhere to happen.
	rewardName: string,
	-- Extra text on the claimed line — the coins that arrive in the same moment.
	-- nil leaves the line naming the skin alone.
	rewardExtra: string?,
	claimed: boolean?,
	size: UDim2?,
	layoutOrder: number?,
}

return function(props: Props)
	local claimed = props.claimed == true

	-- One line, and deliberately not wrapped: it's wider than the HUD's top
	-- column and centred on it, so it overruns evenly on both sides the way the
	-- status line at the bottom does. Wrapping it would buy a ragged second line
	-- for no gain.
	local text = "Get to the next checkpoint for a RARE skin!"
	if claimed then
		text = `{props.rewardName} unlocked!`
		if props.rewardExtra then
			text ..= `  {props.rewardExtra}`
		end
	end

	return React.createElement(ui.Text, {
		text = text,
		textSize = TEXT_SIZE,
		weight = Enum.FontWeight.Heavy,
		shadow = true,
		color = if claimed then CLAIMED_COLOR else PROMISE_COLOR,
		xAlignment = Enum.TextXAlignment.Center,
		size = props.size or UDim2.new(1, 0, 0, LINE_HEIGHT),
		layoutOrder = props.layoutOrder,
	})
end
