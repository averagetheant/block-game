--!strict
-- "Are you still there?" — the card a player gets when the turn order has just
-- dropped them for sitting out two turns running.
--
-- Centred, because that's where a thing the player has to answer belongs (see
-- CLAUDE.md), and because the whole point is that they aren't looking: a
-- notification in a corner is exactly what someone who has wandered off will
-- miss, and they'd come back to a game that had quietly stopped dealing them
-- pieces.
--
-- Two answers, and the colours carry the meaning rather than decorate it: green
-- puts them back in the rotation, red only closes the card. Red is the softer
-- choice here, which is why it isn't the loud one — nothing is lost by pressing
-- it, and the Settings toggle it leaves on is the one they can undo any time.
--
-- Dumb by construction (see docs/game/headless-core.md): it takes two callbacks
-- and a number, and knows nothing about turns, settings or packets.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ui = require(ReplicatedStorage.Shared.Boil).ui

export type Props = {
	-- How many turns went by without them. Shown so the card explains itself
	-- rather than just announcing a verdict.
	missedTurns: number?,
	-- Red: understood, stay out of the rotation.
	onDismiss: (() -> ())?,
	-- Green: put me back in.
	onResume: (() -> ())?,
	zIndex: number?,
}

local WIDTH = 560
-- Both blocks of copy wrap to two lines at this width, and neither is allowed to
-- decide the card's height on the fly — a panel that resized itself around a
-- line break would move the buttons under the player's cursor.
local TITLE_ROWS = 2
local BODY_ROWS = 2
local BUTTON_SIZE = UDim2.fromOffset(220, 76)
local BUTTON_GAP = 16

return function(props: Props)
	local padding = ui.theme.padding + ui.theme.strokeThickness
	local turns = props.missedTurns or 2

	-- Line heights track their text tiers, so a change to the ladder carries the
	-- card with it instead of clipping a descender.
	local titleHeight = ui.theme.textSizeLarge * TITLE_ROWS
	local bodyHeight = ui.theme.textSizeRegular * BODY_ROWS
	local cardHeight = padding * 2
		+ titleHeight
		+ bodyHeight
		+ BUTTON_SIZE.Y.Offset
		+ ui.theme.contentSpacing * 2

	return React.createElement("Frame", {
		-- Full-screen and transparent: the card is centred inside it, and it
		-- catches the clicks that would otherwise land on the HUD behind a modal.
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		ZIndex = props.zIndex,
		Active = true,
	}, {
		Card = React.createElement(ui.Panel, {
			size = UDim2.fromOffset(WIDTH, cardHeight),
			position = UDim2.fromScale(0.5, 0.5),
			anchorPoint = Vector2.new(0.5, 0.5),
			children = {
				Body = React.createElement(ui.Stack, {
					gap = ui.theme.contentSpacing,
					-- Padding, not margin: the panel's stroke sits on its edge,
					-- so content is inset by the stroke as well (see CLAUDE.md).
					padding = padding,
					size = UDim2.fromScale(1, 1),
					horizontalAlignment = Enum.HorizontalAlignment.Center,
					children = {
						Title = React.createElement(ui.Text, {
							text = "You are now no longer playing due to inactivity!",
							textSize = ui.theme.textSizeLarge,
							weight = Enum.FontWeight.Heavy,
							wrapped = true,
							shadow = true,
							size = UDim2.new(1, 0, 0, titleHeight),
							layoutOrder = 1,
						}),

						Detail = React.createElement(ui.Text, {
							text = `You sat out {turns} turns in a row. Say the word and you're back in the rotation.`,
							textSize = ui.theme.textSizeRegular,
							color = Color3.fromRGB(198, 204, 226),
							wrapped = true,
							size = UDim2.new(1, 0, 0, bodyHeight),
							layoutOrder = 2,
						}),

						Actions = React.createElement(ui.Row, {
							gap = BUTTON_GAP,
							size = UDim2.new(1, 0, 0, BUTTON_SIZE.Y.Offset),
							horizontalAlignment = Enum.HorizontalAlignment.Center,
							layoutOrder = 3,
							children = {
								Dismiss = React.createElement(ui.Button, {
									variant = "red",
									text = "OK",
									textSize = ui.theme.textSizeLarge,
									size = BUTTON_SIZE,
									layoutOrder = 1,
									onClick = props.onDismiss,
								}),
								Resume = React.createElement(ui.Button, {
									variant = "green",
									text = "I'm here!",
									textSize = ui.theme.textSizeLarge,
									size = BUTTON_SIZE,
									layoutOrder = 2,
									onClick = props.onResume,
								}),
							},
						}),
					},
				}),
			},
		}),
	})
end
