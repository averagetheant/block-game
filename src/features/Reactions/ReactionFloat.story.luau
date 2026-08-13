--!nonstrict
-- UI Labs story for the float layer. A local Signal stands in for the server's
-- Play broadcast, fired on a timer so the rise, the fade and the fan-out are
-- all visible without a second player.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Features = ReplicatedStorage:WaitForChild("Features")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local Signal = require(ReplicatedStorage.Packages.Signal)
local UILabs = require(ReplicatedStorage.Packages.UILabs)

local Reactions = require(Features:WaitForChild("Reactions"))

return {
	summary = "Reactions in flight: each one rises from just above the bar and fades out, with its horizontal start and drift rolled per reaction so a burst fans out. Drop `interval` to watch the FLOAT_MAX cap drop the oldest.",
	react = React,
	reactRoblox = ReactRoblox,

	controls = {
		interval = UILabs.Slider(0.5, 0.05, 2, 0.05),
	},

	story = function(props)
		local interval = props.controls.interval
		local played = React.useRef(nil)
		if played.current == nil then
			played.current = Signal.new()
		end

		React.useEffect(function()
			local running = true
			task.spawn(function()
				while running do
					local list = Reactions.Catalog.List
					local pick = list[math.random(1, #list)]
					played.current:Fire(pick.id, 0)
					task.wait(interval)
				end
			end)
			return function()
				running = false
			end
		end, { interval })

		return React.createElement(Reactions.Float, {
			played = played.current,
		})
	end,
}
