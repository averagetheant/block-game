-- The TopbarPlus button that opens the daily rewards window.
--
-- Renders nothing itself — TopbarPlus owns its own ScreenGui, so this component
-- exists to tie that icon's lifetime and its selected state to React and to
-- UIShell. It's mounted as a UIRegistry *root* for that reason: a root is
-- always mounted (unlike a screen, which only renders inside an open window),
-- and it sits inside FrameProvider, so it can call useFrame().
--
-- The icon and the frame are kept in step in both directions: clicking the icon
-- opens the frame, and closing the window with its X (or opening some other
-- frame) deselects the icon. Without the second half the topbar would keep
-- showing a highlighted button over a window that isn't there.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Icon = require(ReplicatedStorage.Packages.TopbarPlus)
local UIShell = require(ReplicatedStorage.Features.UIShell)
local Constants = require(ReplicatedStorage.Features.DailyRewards.Constants)

return function()
	local frames = UIShell.useFrame()
	local openFrameId = frames.openFrameId

	local iconRef = React.useRef(nil :: any)
	-- The icon's callbacks are bound once, but `frames` is a fresh table every
	-- time the open frame changes. A ref hands the callbacks the current one
	-- instead of the one that existed at mount — rebinding on every change
	-- would churn the icon's connections for no reason.
	local framesRef = React.useRef(frames)
	framesRef.current = frames

	React.useEffect(function()
		local icon = Icon.new()
			:setName("DailyRewards")
			:setImage(Constants.ICON)
			:setCaption(Constants.TITLE)
			:setOrder(Constants.TOPBAR_ORDER)

		-- Only react to the player actually pressing this button. TopbarPlus
		-- tags every state change with its cause, and "User" is the one that
		-- covers a click, a touch tap and a bound toggle key. The two sources
		-- we must ignore:
		--
		--   * "AutoDeselect" — another topbar icon was selected. That icon's own
		--     handler is already opening its frame, but React state updates
		--     aren't synchronous, so our close() would land afterwards and shut
		--     the frame the player just opened.
		--   * nil — the sync effect below driving us to match frame state, which
		--     is the direction we must not feed back into.
		icon:bindEvent("selected", function(_, fromSource: string?)
			if fromSource ~= "User" then
				return
			end
			framesRef.current.open(Constants.FRAME_ID)
		end)
		icon:bindEvent("deselected", function(_, fromSource: string?)
			if fromSource ~= "User" then
				return
			end
			-- Still only close what we opened.
			if framesRef.current.openFrameId == Constants.FRAME_ID then
				framesRef.current.close()
			end
		end)

		iconRef.current = icon

		return function()
			iconRef.current = nil
			icon:destroy()
		end
	end, {})

	-- Frame state → icon state, so closing the window with its X (or opening
	-- another frame) un-highlights the button. These calls re-fire the events
	-- bound above, but they arrive with a source that isn't "User" and the
	-- guards drop them — which is what stops this effect and those handlers
	-- from driving each other in a circle.
	React.useEffect(function()
		local icon = iconRef.current
		if icon == nil then
			return
		end
		local shouldSelect = openFrameId == Constants.FRAME_ID
		if shouldSelect and not icon.isSelected then
			icon:select()
		elseif not shouldSelect and icon.isSelected then
			icon:deselect()
		end
		return nil
	end, { openFrameId } :: { any })

	return nil
end
