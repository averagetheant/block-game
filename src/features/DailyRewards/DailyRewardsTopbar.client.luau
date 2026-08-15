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
--
-- It also carries the notice — the badge that says today's reward is waiting.
-- The whole point of a daily run is coming back for it, and a run that only
-- announces itself once you've already opened the window announces itself to
-- the players who needed telling least.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Icon = require(ReplicatedStorage.Packages.TopbarPlus)
local Signal = require(ReplicatedStorage.Packages.Signal)
local Boil = require(ReplicatedStorage.Shared.Boil)
local UIShell = require(ReplicatedStorage.Features.UIShell)
local Constants = require(ReplicatedStorage.Features.DailyRewards.Constants)
local Cycle = require(ReplicatedStorage.Features.DailyRewards.Cycle)

-- Client-realm sibling.
local PlayerDataController = require(script.Parent.Parent.PlayerData.PlayerDataController)

-- One notice, replaced rather than stacked: "there is a reward waiting" is a
-- yes/no, and a badge counting to 3 would be claiming three rewards are.
local NOTICE_ID = "DailyRewards.claimable"

return function()
	local frames = UIShell.useFrame()
	local openFrameId = frames.openFrameId

	-- The same arithmetic the window draws itself with, run here because the
	-- button has to know before the window is ever opened.
	local saved = Boil.useReplica(PlayerDataController, Constants.PROFILE_KEY)
	local now, setNow = React.useState(os.time())
	local state = Cycle.resolve(saved, now)
	local claimable = state.canClaim

	local iconRef = React.useRef(nil :: any)
	-- The icon's callbacks are bound once, but `frames` is a fresh table every
	-- time the open frame changes. A ref hands the callbacks the current one
	-- instead of the one that existed at mount — rebinding on every change
	-- would churn the icon's connections for no reason.
	local framesRef = React.useRef(frames)
	framesRef.current = frames

	-- The signal handed to TopbarPlus to clear the notice, which we never fire —
	-- see the notice effect below. One per mount, so it can't outlive its icon.
	local clearNotice = React.useMemo(function()
		return Signal.new()
	end, {})

	-- Nothing writes to the profile at UTC midnight, so the day rolling over is
	-- the one way `canClaim` flips with no replica diff to announce it. One timer
	-- aimed at the boundary rather than a poll: the window's own tick only runs
	-- while it's open, and this button is mounted for the whole session.
	React.useEffect(function()
		local active = true
		task.delay(state.secondsUntilReset + 1, function()
			if active then
				setNow(os.time())
			end
		end)
		return function()
			active = false
		end
	end, { state.secondsUntilReset } :: { any })

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

	-- Claimable → the notice badge, cleared the moment the claim lands (the
	-- replica diff re-renders this and `canClaim` is false).
	--
	-- TopbarPlus clears a notice on its own `deselected` event unless it's given
	-- another one, and that default is wrong here: opening the window and closing
	-- it again without claiming would take the badge away while the reward is
	-- still sitting there. Passing a signal we never fire leaves `clearNotices`
	-- below as the only thing that can retire the badge, so it goes when the
	-- reward does and not before.
	React.useEffect(function()
		local icon = iconRef.current
		if icon == nil then
			return nil
		end
		-- Cleared first either way, so a re-run can't stack a second badge on a
		-- state that's still "one reward waiting".
		icon:clearNotices()
		if claimable then
			icon:notify(clearNotice, NOTICE_ID)
		end
		return nil
	end, { claimable, clearNotice } :: { any })

	return nil
end
