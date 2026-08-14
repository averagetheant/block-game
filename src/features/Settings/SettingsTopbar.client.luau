-- The TopbarPlus button that opens the Settings window.
--
-- Same shape as DailyRewardsTopbar: renders nothing itself, because TopbarPlus
-- owns its own ScreenGui. The component exists to tie the icon's lifetime and
-- its selected state to React and to UIShell, and it's mounted as a UIRegistry
-- *root* so that it's always mounted and sits inside FrameProvider, where it
-- can call useFrame().
--
-- This is a peer of the rail entry (Sidebar.luau) and the world station
-- (SettingsWorldInteraction) — all three open the same UIShell frame and none
-- knows about the others. Turning `Presentations.sidebar` off leaves Settings
-- reachable from here, and vice versa.
--
-- Client realm rather than `.ui.luau` because TopbarPlus reads
-- Players.LocalPlayer and builds its container at require time; the server must
-- never load it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Icon = require(ReplicatedStorage.Packages.TopbarPlus)
local Boil = require(ReplicatedStorage.Shared.Boil)
local UIShell = require(ReplicatedStorage.Features.UIShell)
local Constants = require(ReplicatedStorage.Features.Settings.Constants)

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
			:setName("Settings")
			:setImage(Boil.assets.Icons.settings)
			:setCaption(Constants.TOPBAR_CAPTION)
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

	-- Frame state → icon state, so the icon also lights up when Settings is
	-- opened from the rail or by Settings.linkTo, and clears when the window's
	-- X is used. Guarded on isSelected so this never re-fires the events above.
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
