--!nonstrict
-- UI Labs story for the money readout, shared by the classic HUD and the PVP one.
--
-- The counter pins itself to the bottom-right of whatever it's mounted in, so the
-- story frame is the screen as far as it's concerned.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local Signal = require(ReplicatedStorage.Packages.Signal)
local UILabs = require(ReplicatedStorage.Packages.UILabs)

local CashCounter = require(ReplicatedStorage.Features.TowerGame.CashCounter)

return {
	summary = "The cash counter and its payout burst. `pay` fires an award every few seconds so the bills can be watched landing on the counter; turn it off to read the number on its own.",
	react = React,
	reactRoblox = ReactRoblox,

	controls = {
		cash = UILabs.Slider(1250, 0, 99999, 1),
		-- The burst is the half that can't be eyeballed from a static frame.
		pay = true,
		paySeconds = UILabs.Slider(2, 0.5, 10, 0.5),
	},

	story = function(props)
		local c = props.controls
		-- The real thing takes a signal from TowerFeedbackController. A local one
		-- stands in, driven by the loop below, so the story exercises the same prop
		-- the HUDs pass rather than a story-only shape.
		local awarded = React.useMemo(function()
			return Signal.new()
		end, {})

		React.useEffect(function()
			if not c.pay then
				return
			end
			local running = true
			task.spawn(function()
				while running do
					task.wait(c.paySeconds)
					if running then
						awarded:Fire(50)
					end
				end
			end)
			return function()
				running = false
			end
		end, { c.pay, c.paySeconds })

		return React.createElement(CashCounter, {
			cash = c.cash,
			awarded = awarded,
		})
	end,
}
