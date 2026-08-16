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
}

local TITLE = "Not playing"
local HINT = "You're watching. Turn it off in Settings to take turns."

return function(props: Props)
	-- Content sits clear of the panel's outline, not just its edge (see the
	-- stroke note in CLAUDE.md). Summed at render so a live theme edit moves it.
	local padding = ui.theme.padding + ui.theme.strokeThickness
	local titleHeight = ui.theme.textSizeRegular
	-- The hint wraps to two lines at this width; sized from the tier so a change
	-- to the ladder carries the badge with it rather than clipping a descender.
	local hintHeight = ui.theme.textSizeSmall * 2
	local height = padding * 2 + titleHeight + hintHeight + ui.theme.tightPadding

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
						text = HINT,
						textSize = ui.theme.textSizeSmall,
						color = Color3.fromRGB(198, 204, 226),
						wrapped = true,
						xAlignment = Enum.TextXAlignment.Left,
						yAlignment = Enum.TextYAlignment.Top,
						size = UDim2.new(1, 0, 0, hintHeight),
						layoutOrder = 2,
					}),
				},
			}),
		},
	})
end
