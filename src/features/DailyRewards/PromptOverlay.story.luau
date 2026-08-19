--!nonstrict
-- UI Labs story for the join prompt's two halves.
--
-- In game these are driven by `DailyRewardsPrompt` off the profile replica, which
-- means seeing them for real needs a fresh join with a reward waiting — i.e. one
-- look per UTC day. Here they are two toggles.
--
-- `run` is the one to leave on: it plays the sequence the prompt plays, on a
-- loop — the screen darkens, the player claims (three seconds in), the notice
-- goes up, the window would close, and the notice outlives it by a beat before
-- everything clears. The timings are the shipped constants, so what you're
-- watching is the real pacing.
--
-- The mock panel in the middle stands in for the window. The story mounts no
-- UIShell frame of its own: the point of the overlay is what it does *around* a
-- window, and a stand-in with the right footprint shows the stacking (scrim
-- behind, notice in front) without dragging the whole frame system in.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Features = ReplicatedStorage:WaitForChild("Features")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local ui = require(ReplicatedStorage.Shared.Boil).ui

local DailyRewards = Features:WaitForChild("DailyRewards")
local Constants = require(DailyRewards:WaitForChild("Constants"))
local Layout = require(DailyRewards:WaitForChild("Layout"))
local PromptOverlay = require(DailyRewards:WaitForChild("PromptOverlay"))

-- How long the loop rests with a clear screen before darkening it again. Nothing
-- like a day — this is a story, and the wait is dead time.
local REST_SECONDS = 2

local function Demo(props)
	local scrim, setScrim = React.useState(props.scrim)
	local notice, setNotice = React.useState(props.notice)

	React.useEffect(function()
		if not props.run then
			setScrim(props.scrim)
			setNotice(props.notice)
			return
		end

		local running = true
		task.spawn(function()
			while running do
				-- Join: the screen darkens and the window is up.
				setScrim(true)
				setNotice(false)
				task.wait(Constants.CLOSE_SECONDS)
				if not running then
					break
				end
				-- Claimed: the notice goes up, and the window has CLOSE_SECONDS left.
				setNotice(true)
				task.wait(Constants.CLOSE_SECONDS)
				setScrim(false)
				-- The notice outlives the window by the difference between the two.
				task.wait(math.max(Constants.NOTICE_SECONDS - Constants.CLOSE_SECONDS, 0))
				setNotice(false)
				task.wait(REST_SECONDS)
			end
		end)

		return function()
			running = false
		end
	end, { props.run, props.scrim, props.notice })

	local windowSize = Layout.windowSize()

	return React.createElement(ui.Slot, {
		size = UDim2.fromScale(1, 1),
	}, {
		-- Something to be behind and in front of. Stands in for the HUD as much as
		-- for the window: it's the thing the scrim is supposed to dim.
		Window = React.createElement(ui.Panel, {
			size = windowSize,
			position = UDim2.fromScale(0.5, 0.5),
			anchorPoint = Vector2.new(0.5, 0.5),
			zIndex = Constants.WINDOW_ZINDEX,
		}, {
			Label = React.createElement(ui.Text, {
				text = "the window goes here",
				textSize = ui.theme.textSizeLarge,
				weight = Enum.FontWeight.Heavy,
				size = UDim2.fromScale(1, 1),
			}),
		}),

		Overlay = React.createElement(PromptOverlay, {
			scrim = scrim,
			notice = notice,
		}),
	})
end

return {
	summary = "The join prompt's scrim and notice. `run` loops the real sequence — darken, claim, notice, close — at the shipped timings; turn it off to hold either half up on its own.",
	react = React,
	reactRoblox = ReactRoblox,

	controls = {
		run = true,
		scrim = true,
		notice = false,
	},

	story = function(props)
		local c = props.controls
		return React.createElement(Demo, {
			run = c.run,
			scrim = c.scrim,
			notice = c.notice,
		})
	end,
}
