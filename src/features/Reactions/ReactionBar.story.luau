--!nonstrict
-- UI Labs story for the reaction bar. Click the arrow tab to slide it in and
-- out; clicking a reaction prints instead of sending (there's no server here).
--
-- The bar anchors itself to the right edge of whatever it's mounted in, so in
-- Labs it sits against the side of the preview pane rather than the screen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Features = ReplicatedStorage:WaitForChild("Features")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local UILabs = require(ReplicatedStorage.Packages.UILabs)

local Reactions = require(Features:WaitForChild("Reactions"))

local PACK_SLOTS = { "fire", "skull", "clap", "rocket" }

return {
	summary = "The reaction bar: white, minimal, closed by default — a vertical column down the right edge, vertically centred, sliding out to the right. The arrow tab on its left edge toggles it. Switch `slots` to the pack set to see three emoji and one *image* reaction stacked together — both kinds render through the same glyph component.",
	react = React,
	reactRoblox = ReactRoblox,

	controls = {
		slots = UILabs.Choose({ "default", "pack" }),
		initialOpen = true,
	},

	story = function(props)
		local c = props.controls
		local slots = if c.slots == "pack" then PACK_SLOTS else Reactions.Catalog.DEFAULT_SLOTS

		return React.createElement(Reactions.Bar, {
			slots = slots,
			initialOpen = c.initialOpen,
			onSend = function(id)
				print(`[Reactions] send {id}`)
			end,
		})
	end,
}
