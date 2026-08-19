-- The TopbarPlus button that opens Roblox's feedback panel.
--
-- Same shape as SettingsTopbar and DailyRewardsTopbar: it renders nothing itself
-- (TopbarPlus owns its own ScreenGui) and exists to tie an icon's lifetime to
-- React. It's mounted as a UIRegistry *root* for the same reason they are — a
-- root is always mounted, where a screen only renders inside an open window.
--
-- What it does *not* share with those two is the UIShell dance. They open a frame
-- this game draws, so their icons have a selected state to keep in step with it.
-- This one hands the screen to Roblox and gets it back: there is no frame, so the
-- icon is `oneClick` and never stays lit. An icon left highlighted in front of a
-- panel the experience doesn't own would be claiming a toggle it doesn't have.
--
-- Client realm rather than `.ui.luau` because both halves are client-only:
-- TopbarPlus reads Players.LocalPlayer and builds its container at require time,
-- and `PromptFeedbackSubmissionAsync` is a client call.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local React = require(ReplicatedStorage.Packages.React)
local Icon = require(ReplicatedStorage.Packages.TopbarPlus)
local Constants = require(ReplicatedStorage.Features.Feedback.Constants)

-- Open the panel.
--
-- Wrapped in a pcall because this throws rather than returning a result when it
-- can't be shown — an older client, a platform without the panel, the Social
-- capability switched off for the place, or a second prompt asked for while one
-- is already up. A button that can't open the panel should do nothing visible
-- rather than break the script that owns the topbar.
--
-- Spawned rather than called inline: it **yields** for as long as the player has
-- the panel open, and the thread it's called on is TopbarPlus's own event.
local function prompt()
	task.spawn(function()
		local ok, err = pcall(function()
			SocialService:PromptFeedbackSubmissionAsync({ FeedbackType = Constants.TYPE })
		end)
		if not ok then
			warn(`[Feedback] couldn't open the feedback panel: {err}`)
		end
	end)
end

return function()
	React.useEffect(function()
		local icon = Icon.new()
			:setName("Feedback")
			:setImage(Constants.ICON)
			-- Labelled, not just pictured: the icon widens to fit the word, and a
			-- player reading the topbar doesn't have to hover a question mark to
			-- find out it isn't the help button.
			:setLabel(Constants.LABEL)
			:setCaption(Constants.CAPTION)
			:setOrder(Constants.TOPBAR_ORDER)
			:align(Constants.ALIGNMENT)
			-- Deselects itself the moment it's pressed. See the note above.
			:oneClick(true)

		-- Only the player pressing it. TopbarPlus tags every state change with its
		-- cause, and "User" is the one that covers a click, a touch tap and a bound
		-- toggle key — the others are the library's own bookkeeping (including the
		-- `oneClick` deselect this very handler causes), and opening Roblox's panel
		-- off one of those would be a prompt nobody asked for.
		icon:bindEvent("selected", function(_, fromSource: string?)
			if fromSource ~= "User" then
				return
			end
			prompt()
		end)

		return function()
			icon:destroy()
		end
	end, {})

	return nil
end
