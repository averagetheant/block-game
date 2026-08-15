-- Stateful container: profile slice in, resolved run out.
--
-- Two things drive a re-render. The replica diff is one — claiming writes
-- Streak/LastClaim and the cards move. The other is the clock: `secondsUntilReset`
-- has to count down, and at UTC midnight `canClaim` flips with no packet and no
-- write to announce it. So the tick is what makes tomorrow's reward appear for a
-- player who left the window open overnight.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

local Boil = require(ReplicatedStorage.Shared.Boil)
local DailyRewards = require(ReplicatedStorage.Features.DailyRewards)
local Constants = require(ReplicatedStorage.Features.DailyRewards.Constants)
local Cycle = require(ReplicatedStorage.Features.DailyRewards.Cycle)

-- Client-realm siblings.
local DailyRewardsController = require(script.Parent.DailyRewardsController)
local PlayerDataController = require(script.Parent.Parent.PlayerData.PlayerDataController)
local AnalyticsController = require(script.Parent.Parent.Analytics.AnalyticsController)

return function()
	local saved = Boil.useReplica(PlayerDataController, Constants.PROFILE_KEY)
	local now, setNow = React.useState(os.time())

	-- Step 2 of the daily funnel. A `step` rather than a `start`: the session is
	-- the *run*, opened server-side and keyed by the run's start date, so
	-- opening a new one here would split one seven-day journey into two rows.
	React.useEffect(function()
		AnalyticsController.step("daily", "Window Opened")
	end, {})

	React.useEffect(function()
		local running = true
		task.spawn(function()
			while running do
				task.wait(Constants.COUNTDOWN_TICK)
				if running then
					setNow(os.time())
				end
			end
		end)
		return function()
			running = false
		end
	end, {})

	-- Resolved client-side purely so the window can draw itself. The server
	-- re-resolves on every claim and ignores what the client concluded — this
	-- is the same arithmetic, not a second authority.
	local state = Cycle.resolve(saved, now)

	return React.createElement(DailyRewards.UI, {
		days = DailyRewards.listDays(),
		state = state,
		onClaim = DailyRewardsController.claim,
	})
end
