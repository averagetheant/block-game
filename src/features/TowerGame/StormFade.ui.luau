--!strict
-- The white-out when the storm takes the tower.
--
-- A one-shot flash rather than a state: `active` going true plays the whole
-- sequence — wait, fade to white, hold, clear — and it does not stay white for
-- as long as `active` is. That matters because the round break holds
-- PHASE.GAMEOVER for the length of the gamemode vote, and a sheet that tracked
-- the phase would sit over the ballot for all of it.
--
-- The delay before the fade starts is the point of the effect: the storm throwing
-- the tower off the plane is the thing worth watching, so the blocks fly first
-- and the screen goes white over the tail of it.
--
-- TweenService drives the transparency off a ref, so a two-second animation
-- costs no re-renders.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local React = require(ReplicatedStorage.Packages.React)
local Constants = require(script.Parent.Constants)

export type Props = {
	-- True while the round is over. The rising edge is what plays the flash.
	active: boolean,
	-- Above every other HUD child; this covers the screen, HUD included.
	zIndex: number?,
}

return function(props: Props)
	local sheet = React.useRef(nil :: Frame?)

	React.useEffect(function()
		local frame = sheet.current
		if not props.active or frame == nil then
			return
		end

		local fadeIn = TweenService:Create(
			frame,
			TweenInfo.new(
				Constants.STORM_FADE_IN_SECONDS,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out,
				0,
				false,
				Constants.STORM_FADE_DELAY_SECONDS
			),
			{ BackgroundTransparency = 0 }
		)
		local fadeOut = TweenService:Create(
			frame,
			TweenInfo.new(
				Constants.STORM_FADE_OUT_SECONDS,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.In,
				0,
				false,
				Constants.STORM_FADE_HOLD_SECONDS
			),
			{ BackgroundTransparency = 1 }
		)

		local alive = true
		fadeIn:Play()
		fadeIn.Completed:Once(function()
			if alive then
				fadeOut:Play()
			end
		end)

		-- A round that ends while the flash is still running (a Nuke bought during
		-- the wreck) must not leave the screen stuck white.
		return function()
			alive = false
			fadeIn:Cancel()
			fadeIn:Destroy()
			fadeOut:Cancel()
			fadeOut:Destroy()
			frame.BackgroundTransparency = 1
		end
	end, { props.active })

	return React.createElement("Frame", {
		ref = sheet,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		-- Starts clear and is only ever moved by the tweens above.
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = props.zIndex,
		-- Nothing under a full-screen sheet should stop being clickable because of
		-- it — the reaction bar and the vote both live under this.
		Active = false,
	})
end
