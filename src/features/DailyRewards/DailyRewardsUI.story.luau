--!nonstrict
-- UI Labs story for the daily rewards window.
--
-- Mounts the real UI inside a ui.Window sized by the same Layout the feature
-- uses, so what you see here is what the topbar button opens — the story adds
-- chrome, not layout.
--
-- The controls drive the two inputs the feature can't show you from a live
-- profile: where the player is in the run, and how big the cards are. Run
-- state is built by hand rather than by resolving a fake profile, because the
-- interesting cases (mid-run, everything claimed, a wrapped run) are three
-- clicks apart here and three days apart in the game.
--
-- The days come from the live registry — whatever the installed features
-- registered — so an unregistered slot shows as a "???" card here exactly as
-- it would in game.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local UILabs = require(ReplicatedStorage.Packages.UILabs)
local ui = require(ReplicatedStorage.Shared.Boil).ui

local DailyRewards = require(ReplicatedStorage.Features.DailyRewards)
local Constants = require(ReplicatedStorage.Features.DailyRewards.Constants)
local Layout = require(ReplicatedStorage.Features.DailyRewards.Layout)

local HOUR = 3600

return {
	summary = "Daily rewards — the non-grand days in a grid plus a tall grand-prize card. "
		.. "`claimedThrough` is how far the run has got; `canClaim` opens the next day. "
		.. "Days come from the live registry, so an unregistered slot draws as ???.",
	react = React,
	reactRoblox = ReactRoblox,

	controls = {
		claimedThrough = UILabs.Slider(2, 0, Constants.CYCLE_DAYS, 1),
		canClaim = true,
		hoursUntilReset = UILabs.Slider(9, 0, 24, 1),
		squareSize = UILabs.Slider(Constants.SQUARE_SIZE, 150, 300, 5),
		grandWidth = UILabs.Slider(Constants.GRAND_WIDTH, 200, 440, 5),
	},

	story = function(props)
		local c = props.controls

		-- Hand-built rather than resolved from a fake profile: the point of the
		-- story is to park the UI in a state, not to re-test Cycle's arithmetic.
		-- nextDay wraps the same way Cycle does so the grand day can be the live
		-- one at the end of a run.
		local state = {
			nextDay = (c.claimedThrough % Constants.CYCLE_DAYS) + 1,
			canClaim = c.canClaim,
			claimedThrough = c.claimedThrough,
			broken = false,
			secondsUntilReset = c.hoursUntilReset * HOUR,
		}

		local content = React.createElement(DailyRewards.UI, {
			days = DailyRewards.listDays(),
			state = state,
			squareSize = c.squareSize,
			grandWidth = c.grandWidth,
			onClaim = function(day)
				print(`[DailyRewardsUI.story] claim day {day}`)
			end,
		})

		-- Window sized from the same metrics the story is driving, so dragging
		-- a card slider resizes the chrome instead of clipping the grid.
		local metrics = Layout.metrics(c.squareSize, c.grandWidth)
		local theme = ui.theme
		local size = UDim2.fromOffset(
			metrics.contentWidth + theme.padding * 2,
			theme.topBarHeight
				+ (theme.padding + theme.strokeThickness)
				+ metrics.contentHeight
				+ theme.padding
		)

		return React.createElement(ui.Window, {
			size = size,
			title = Constants.TITLE,
			icon = Constants.ICON,
			titleVariant = Constants.TITLE_VARIANT,
			position = UDim2.fromScale(0.5, 0.5),
			anchorPoint = Vector2.new(0.5, 0.5),
			onClose = function()
				print("[DailyRewardsUI.story] close")
			end,
		}, {
			Content = content,
		})
	end,
}
