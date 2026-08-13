--!nonstrict
-- UI Labs story for ScaleLayer. The bordered box is a stand-in screen; the
-- content inside it is laid out the way a real HUD is — a readout pinned to the
-- top edge, a rail on the left, a button in the bottom-right corner — all in
-- plain pixel offsets, exactly as a feature writes them.
--
-- Drag `scale` down to see what a small screen gets. Everything shrinks together
-- and stays anchored to its own edge; the margins shrink with it rather than
-- staying fat around tiny content. In game this number isn't a slider — the root
-- ScaleLayer reads it from the viewport via useViewportScale.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local UILabs = require(ReplicatedStorage.Packages.UILabs)
local ui = require(ReplicatedStorage.Shared.ui)

local EDGE = 20

return {
	summary = "Root viewport scale. Drag `scale` to preview the HUD on a smaller screen — offsets shrink, edge anchors hold.",
	react = React,
	reactRoblox = ReactRoblox,

	controls = {
		scale = UILabs.Slider(1, 0.4, 1, 0.05),
	},

	story = function(props)
		return React.createElement("Frame", {
			-- The mock screen. Fixed size on purpose: only the contents scale, so
			-- the box is the constant you're reading the change against.
			Size = UDim2.fromOffset(720, 405),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.fromRGB(28, 32, 44),
			BorderSizePixel = 0,
			ClipsDescendants = true,
		}, {
			Layer = React.createElement(ui.ScaleLayer, { scale = props.controls.scale }, {
				Readout = React.createElement(ui.Panel, {
					size = UDim2.fromOffset(420, 62),
					position = UDim2.new(0.5, 0, 0, EDGE),
					anchorPoint = Vector2.new(0.5, 0),
				}, {
					Label = React.createElement(ui.Text, {
						text = "0.0 studs",
						textSize = 30,
						weight = Enum.FontWeight.Heavy,
						shadow = true,
						xAlignment = Enum.TextXAlignment.Center,
						size = UDim2.fromScale(1, 1),
					}),
				}),

				Rail = React.createElement(ui.Stack, {
					gap = 12,
					size = UDim2.fromOffset(72, 72 * 3 + 12 * 2),
					position = UDim2.new(0, EDGE, 0.5, 0),
					anchorPoint = Vector2.new(0, 0.5),
				}, {
					One = React.createElement(ui.IconButton, {
						icon = ui.assets.Icons.magnifyingGlass,
						variant = "blue",
						size = UDim2.fromOffset(72, 72),
						layoutOrder = 1,
					}),
					Two = React.createElement(ui.IconButton, {
						icon = ui.assets.Icons.magnifyingGlass,
						variant = "green",
						size = UDim2.fromOffset(72, 72),
						layoutOrder = 2,
					}),
					Three = React.createElement(ui.IconButton, {
						icon = ui.assets.Icons.magnifyingGlass,
						variant = "purple",
						size = UDim2.fromOffset(72, 72),
						layoutOrder = 3,
					}),
				}),

				Action = React.createElement(ui.Button, {
					variant = "red",
					text = "DROP",
					size = UDim2.fromOffset(160, 88),
					position = UDim2.new(1, -EDGE, 1, -EDGE),
					anchorPoint = Vector2.new(1, 1),
				}),
			}),
		})
	end,
}
