-- The frame itself: UIShell.Frame (open/close state + enter tween) wrapping a
-- ui.Window (chrome) wrapping the View (content).
--
-- Most windows in this game are opened from the Sidebar rail, which renders the
-- Frame and Window for every rail entry it knows about. This one's entry point
-- is the topbar, and the rail only builds windows for rail entries — so the
-- feature mounts its own. That also means it owns its chrome: the title badge
-- carries the same icon as the topbar button, so the thing you click and the
-- thing that opens read as one object.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ui = require(ReplicatedStorage.Shared.Boil).ui
local UIShell = require(ReplicatedStorage.Features.UIShell)
local Constants = require(ReplicatedStorage.Features.DailyRewards.Constants)
local Layout = require(ReplicatedStorage.Features.DailyRewards.Layout)

-- Client-realm siblings.
local DailyRewardsPrompt = require(script.Parent.DailyRewardsPrompt)
local DailyRewardsView = require(script.Parent.DailyRewardsView)

return function()
	local frames = UIShell.useFrame()

	-- Three things in one root, stacked: the prompt's scrim, the window, the
	-- prompt's notice. They have to share a root — the scrim goes *under* the
	-- window and the notice *over* it, and only siblings can be sorted against
	-- each other.
	--
	-- The root itself sits on `ui.layers.window`, which is what puts the whole set
	-- above every HUD. Left on the default it drew in registration order, so
	-- whether the window came out in front of the PVP standings board was down to
	-- how a table iterated that session.
	return React.createElement(ui.Slot, {
		name = "DailyRewards",
		size = UDim2.fromScale(1, 1),
		zIndex = ui.layers.window,
	}, {
		Prompt = React.createElement(DailyRewardsPrompt),

		Frame = React.createElement(UIShell.Frame, {
			id = Constants.FRAME_ID,
			zIndex = Constants.WINDOW_ZINDEX,
		}, {
			-- Frame clones its children with `scaleRef` / `initialScale`, which
			-- Window accepts — that's what makes the window scale from its own
			-- centre on open rather than from the screen's.
			Window = React.createElement(ui.Window, {
				-- Derived from the card geometry, so a card size change moves the
				-- window instead of putting a scrollbar on it.
				size = Layout.windowSize(),
				title = Constants.TITLE,
				icon = Constants.ICON,
				titleVariant = Constants.TITLE_VARIANT :: any,
				onClose = frames.close,
			}, {
				Content = React.createElement(DailyRewardsView),
			}),
		}),
	})
end
