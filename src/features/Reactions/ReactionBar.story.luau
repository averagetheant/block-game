--!nonstrict
-- UI Labs story for the reaction bar. Click the arrow tab to slide it in and
-- out; clicking a reaction prints instead of sending (there's no server here).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Features = ReplicatedStorage:WaitForChild("Features")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local UILabs = require(ReplicatedStorage.Packages.UILabs)

local Reactions = require(Features:WaitForChild("Reactions"))

local PACK_SLOTS = { "fire", "skull", "clap", "rocket" }

return {
	summary = "The reaction bar: white, minimal, closed by default. The arrow tab toggles it. Switch `slots` to the pack set to see three emoji and one *image* reaction sitting side by side — both kinds render through the same glyph component.",
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
