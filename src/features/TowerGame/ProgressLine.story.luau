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
--
-- `goalLabel` caps the rail with a deadline above the goal dot. TowerGame's HUD
-- keeps its storm clock in the top column instead, so nothing ships with this on
-- today — it's a capability of the component, exercised here. Turn it on and push
-- `current` all the way to `to`: the marker's own readout ends up at the goal
-- dot, and the two labels have to still clear each other there.

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

-- The deadline above the goal dot, and the colour the HUD gives it once the
-- storm is close. Same two states TowerHUD picks between.
local GOAL_LABELS = {
	["Storm in 4:33"] = { text = "Storm in 4:33", color = Color3.fromRGB(226, 230, 245) },
	["Storm in 0:09"] = { text = "Storm in 0:09", color = Color3.fromRGB(255, 138, 122) },
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
		goalLabel = UILabs.Choose({ "Storm in 4:33", "Storm in 0:09", "none" }),
	},

	story = function(props)
		local c = props.controls
		local goal = GOAL_LABELS[c.goalLabel]

		return React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
		}, {
			Rail = React.createElement(ProgressLine, {
				from = c.from,
				current = c.current,
				to = c.to,
				label = LABELS[c.label],
				goalLabel = if goal then goal.text else nil,
				goalColor = if goal then goal.color else nil,
				size = UDim2.fromOffset(RAIL_WIDTH, RAIL_HEIGHT),
				-- Right of centre rather than dead centre, so the readout hanging
				-- off the marker's left has the room it has in the HUD.
				position = UDim2.fromScale(0.7, 0.5),
				anchorPoint = Vector2.new(0.5, 0.5),
			}),
		})
	end,
}
