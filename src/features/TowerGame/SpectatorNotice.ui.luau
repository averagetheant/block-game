--!strict
-- The small "you're out of the rotation" badge, up for as long as the player is
-- in "Not playing" — however they got there, benched for inactivity or by their
-- own hand in Settings.
--
-- Deliberately not a second card. The card is a *moment* (you were just taken
-- out, here's the way back) and it is answered and dismissed; this is a *state*,
-- and a state that keeps interrupting is worse than the thing it's warning about.
-- So it sits in a corner nothing else uses and says two things: that turns aren't
-- coming, and where to change that.
--
-- It also covers the case the card can't: a player who dismissed it, or joined a
-- session already benched, or looked away at the wrong moment. Without this, the
-- only evidence of being out of the game is turns quietly never arriving — which
-- is indistinguishable from the game being broken.
--
-- Dumb by construction (see docs/game/headless-core.md): no props at all beyond
-- placement. Whether it should exist is TowerAfkView's question.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ui = require(ReplicatedStorage.Shared.Boil).ui
local Constants = require(script.Parent.Constants)

export type Props = {
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
	-- Puts the way back on the badge itself. Optional: without it the badge is
	-- the pure state readout it started as, which is what the story renders.
	onResume: (() -> ())?,
}

local TITLE = "Not playing"
-- Two hints, because the badge says two different things depending on whether the
-- way back is on it. With the button, Settings is the *other* route and naming it
-- first would send the player the long way round.
local HINT = "You're watching. Turn it off in Settings to take turns."
local HINT_WITH_BUTTON = "You're watching. Take turns again whenever you like."
-- Breathing room on top of `tier * rows` — see hintHeight below.
local ROW_SLACK = 8
-- Small on purpose. This is a standing badge, not a prompt: the button is the
-- convenience, and a full-width call to action would make a state readout look
-- like something demanding an answer.
local BUTTON_WIDTH = 150
local BUTTON_HEIGHT = 44

return function(props: Props)
	-- Content sits clear of the panel's outline, not just its edge (see the
	-- stroke note in CLAUDE.md). Summed at render so a live theme edit moves it.
	local padding = ui.theme.padding + ui.theme.strokeThickness
	local titleHeight = ui.theme.textSizeRegular
	-- The hint wraps to two lines at this width; sized from the tier so a change
	-- to the ladder carries the badge with it rather than clipping a descender.
	-- The slack is what absorbs the pixel a line picks up when the viewport
	-- scale rounds it — at exactly `tier * rows` the second line is dropped
	-- instead of squeezed.
	local hintHeight = ui.theme.textSizeSmall * 2 + ROW_SLACK
	-- One gap per seam between rows, so the button's arrival adds its own height
	-- and one more gap rather than being crammed into the old box.
	local resume = props.onResume
	local height = padding * 2
		+ titleHeight
		+ hintHeight
		+ ui.theme.tightPadding
		+ (if resume then BUTTON_HEIGHT + ui.theme.tightPadding else 0)

	return React.createElement(ui.Panel, {
		size = UDim2.fromOffset(Constants.SPECTATOR_NOTICE_WIDTH, height),
		position = props.position,
		anchorPoint = props.anchorPoint,
		layoutOrder = props.layoutOrder,
		zIndex = props.zIndex,
		children = {
			Body = React.createElement(ui.Stack, {
				gap = ui.theme.tightPadding,
				padding = padding,
				size = UDim2.fromScale(1, 1),
				horizontalAlignment = Enum.HorizontalAlignment.Left,
				children = {
					Title = React.createElement(ui.Text, {
						text = TITLE,
						textSize = ui.theme.textSizeRegular,
						weight = Enum.FontWeight.Heavy,
						-- The tell colour the "Not playing" toggle already wears
						-- in Settings, so the two read as the same switch.
						color = Constants.SPECTATOR_NOTICE_COLOR,
						xAlignment = Enum.TextXAlignment.Left,
						size = UDim2.new(1, 0, 0, titleHeight),
						layoutOrder = 1,
					}),

					Hint = React.createElement(ui.Text, {
						text = if resume then HINT_WITH_BUTTON else HINT,
						textSize = ui.theme.textSizeSmall,
						color = Color3.fromRGB(198, 204, 226),
						wrapped = true,
						xAlignment = Enum.TextXAlignment.Left,
						yAlignment = Enum.TextYAlignment.Top,
						size = UDim2.new(1, 0, 0, hintHeight),
						layoutOrder = 2,
					}),

					-- Green like the card's own way back, so the two read as the
					-- same door — but "PLAY" rather than the card's "I'm here!".
					-- The card is answering an accusation (you sat out three
					-- turns); this is a standing switch, and a switch is labelled
					-- with what it does.
					Resume = if resume
						then React.createElement(ui.Button, {
							text = "PLAY",
							variant = "green",
							size = UDim2.fromOffset(BUTTON_WIDTH, BUTTON_HEIGHT),
							onClick = resume,
							layoutOrder = 3,
						})
						else nil,
				},
			}),
		},
	})
end
