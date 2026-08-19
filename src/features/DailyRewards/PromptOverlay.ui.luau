--!strict
-- The two halves of the join prompt: the scrim that darkens everything behind
-- the window, and the notice that says when to come back.
--
-- Dumb by construction — two booleans in, no state, no clock, no idea what a
-- claim is. `DailyRewardsPrompt` owns when each one is up; this owns what they
-- look like, which is the split that lets the whole thing be looked at in UI Labs
-- without a profile, a server or a seven-day wait.
--
-- **A Fragment, not a container.** The two halves live on *either side* of the
-- window in the stack — the scrim under it, the notice over it — and only
-- siblings sort against each other. Wrapping them in a frame of their own would
-- put both on the same side of it, which is the one arrangement that can't work.
-- The window and these are all children of the feature's single root; see
-- `DailyRewardsWindow`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local React = require(ReplicatedStorage.Packages.React)
local ui = require(ReplicatedStorage.Shared.Boil).ui
local Constants = require(script.Parent.Constants)

-- How far the notice sits off the bottom of the screen. Below the window's own
-- footer, so the two don't argue about which line to read.
local NOTICE_MARGIN = 24
local NOTICE_TWEEN = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

export type Props = {
	-- Darken everything behind the window.
	scrim: boolean?,
	-- Put the "come back tomorrow" card up over it.
	notice: boolean?,
}

-- Everything that isn't the reward, dimmed.
--
-- It swallows the click as well as the light: while it's up, the only live
-- controls on screen are the ones drawn above it — the Claim button and the
-- window's X. That is the whole trick. A dimmed HUD you can still press is a
-- decoration; one you can't is an instruction.
local function Scrim()
	local frame = React.useRef(nil :: Frame?)

	-- Faded in rather than cut in. The window arrives on a Back/Out scale tween
	-- (UIShell.Frame) and a scrim that snapped to full black under it would beat
	-- the window to the screen, which reads as a loading screen rather than as the
	-- game stepping back.
	React.useEffect(function()
		local instance = frame.current
		if instance == nil then
			return
		end
		local tween = TweenService:Create(
			instance,
			TweenInfo.new(Constants.SCRIM_FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = Constants.SCRIM_TRANSPARENCY }
		)
		tween:Play()
		return function()
			tween:Cancel()
			tween:Destroy()
		end
	end, {})

	return React.createElement("Frame", {
		ref = frame,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Constants.SCRIM_COLOR,
		-- Starts invisible; the effect above tweens it to SCRIM_TRANSPARENCY.
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = true,
		ZIndex = Constants.SCRIM_ZINDEX,
	})
end

-- "Come back tomorrow for your next daily reward!" — the sentence the whole
-- mechanism exists to make true, said at the one moment it's provably true.
local function Notice()
	local shown, setShown = React.useState(false)
	React.useEffect(function()
		setShown(true)
	end, {})
	local scaleRef = ui.useTweenedScale(if shown then 1 else 0, { tweenInfo = NOTICE_TWEEN })

	return React.createElement(ui.Slot, {
		name = "DailyRewardsNotice",
		size = UDim2.fromOffset(Constants.NOTICE_WIDTH, Constants.NOTICE_HEIGHT),
		position = UDim2.new(0.5, 0, 1, -NOTICE_MARGIN),
		anchorPoint = Vector2.new(0.5, 1),
		zIndex = Constants.NOTICE_ZINDEX,
	}, {
		Scale = React.createElement("UIScale", { Scale = 0, ref = scaleRef }),
		Card = React.createElement(ui.Panel, {
			size = UDim2.fromScale(1, 1),
			-- The same variant as the window's title badge, so the notice reads as
			-- that window still talking rather than as a second thing arriving.
			variant = Constants.TITLE_VARIANT :: any,
		}, {
			Body = React.createElement(ui.Text, {
				text = Constants.NOTICE_TEXT,
				textSize = ui.theme.textSizeLarge,
				weight = Enum.FontWeight.Heavy,
				shadow = true,
				wrapped = true,
				-- Padded against the panel's stroked edge, read at render time so a
				-- live theme edit follows.
				size = UDim2.new(1, -(ui.theme.padding + ui.theme.strokeThickness) * 2, 1, 0),
				position = UDim2.fromScale(0.5, 0.5),
				anchorPoint = Vector2.new(0.5, 0.5),
			}),
		}),
	})
end

return function(props: Props)
	local children: { [string]: any } = {}
	if props.scrim then
		children.Scrim = React.createElement(Scrim)
	end
	if props.notice then
		children.Notice = React.createElement(Notice)
	end
	if next(children) == nil then
		return nil
	end

	return React.createElement(React.Fragment, nil, children)
end
