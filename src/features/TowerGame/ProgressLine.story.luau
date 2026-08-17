--!nonstrict
-- UI Labs story for the climb rail — the vertical progress line the HUD pins to
-- the right of the screen.
--
-- The thing worth watching here is the *glide*: drag `current` and the marker
-- and its trail tween to the new spot rather than jumping, because in game the
-- height arrives in steps (a block lands, the number jumps). Park `current`
-- below `from` or above `to` to check the clamp — a tower can be under the leg's
-- base right after a checkpoint clears, and over the target for the moment
-- before the stage does.
--
-- `label` is what rides beside the marker. Empty renders the marker alone;
-- the long reading is here to check it stays clear of the rail as it climbs.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Features = ReplicatedStorage:WaitForChild("Features")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local UILabs = require(ReplicatedStorage.Packages.UILabs)

local TowerGame = Features:WaitForChild("TowerGame")
local ProgressLine = require(TowerGame:WaitForChild("ProgressLine"))

local LABELS = {
	["24.5 studs"] = "24.5 studs",
	["1234.5 studs"] = "1234.5 studs",
	["none"] = nil,
}

-- The rail's own footprint in the HUD (RAIL_WIDTH, and a height in the same
-- ballpark as the band it gets between the topbar and the cash corner).
local RAIL_WIDTH = 24
local RAIL_HEIGHT = 420

return {
	summary = "The climb to the next checkpoint, drawn as a vertical rail: bottom dot where this leg started, top dot where it clears, and a marker riding between them with the height readout attached. Drag `current` to watch it glide.",
	react = React,
	reactRoblox = ReactRoblox,

	controls = {
		from = UILabs.Slider(0, 0, 600, 1),
		current = UILabs.Slider(24.5, 0, 600, 0.5),
		to = UILabs.Slider(40, 0, 600, 1),
		label = UILabs.Choose({ "24.5 studs", "1234.5 studs", "none" }),
	},

	story = function(props)
		local c = props.controls

		return React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
		}, {
			Rail = React.createElement(ProgressLine, {
				from = c.from,
				current = c.current,
				to = c.to,
				label = LABELS[c.label],
				size = UDim2.fromOffset(RAIL_WIDTH, RAIL_HEIGHT),
				-- Right of centre rather than dead centre, so the readout hanging
				-- off the marker's left has the room it has in the HUD.
				position = UDim2.fromScale(0.7, 0.5),
				anchorPoint = Vector2.new(0.5, 0.5),
			}),
		})
	end,
}
