--!strict
-- The payout flourish: a burst of bills that erupts from the middle of the
-- screen and converges on the cash counter.
--
-- Deliberately not React-driven per frame. Rendering a dozen images and moving
-- them with state would re-render the whole HUD every frame of the animation;
-- instead each burst builds plain instances under one host Frame, hands them to
-- TweenService, and cleans up after itself. React owns the host, not the bills.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local React = require(ReplicatedStorage.Packages.React)
local Constants = require(script.Parent.Constants)

export type Props = {
	-- Fires with an amount each time cash arrives.
	awarded: any,
	-- Where the bills are heading, in scale coords (the counter's position).
	target: UDim2,
}

local BILL_SIZE = 46
-- How far off centre a bill starts, so the burst reads as a spray rather than a
-- single stack sliding across the screen.
local SPREAD = 90

local function fly(host: Frame, target: UDim2)
	for index = 1, Constants.CASH_FLY_COUNT do
		local bill = Instance.new("ImageLabel")
		bill.Image = Constants.CASH_IMAGE
		bill.BackgroundTransparency = 1
		bill.Size = UDim2.fromOffset(BILL_SIZE, BILL_SIZE)
		bill.AnchorPoint = Vector2.new(0.5, 0.5)
		bill.Position = UDim2.new(
			0.5,
			math.random(-SPREAD, SPREAD),
			0.5,
			math.random(-SPREAD, SPREAD)
		)
		bill.Rotation = math.random(-40, 40)
		bill.ZIndex = 10
		bill.Parent = host

		-- Stagger the departures so the burst drains toward the counter instead
		-- of teleporting there as one clump.
		local delay = (index - 1) * 0.03
		local info = TweenInfo.new(
			Constants.CASH_FLY_SECONDS,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In,
			0,
			false,
			delay
		)

		local tween = TweenService:Create(bill, info, {
			Position = target,
			Size = UDim2.fromOffset(BILL_SIZE * 0.4, BILL_SIZE * 0.4),
			ImageTransparency = 1,
			Rotation = 0,
		})
		tween:Play()
		tween.Completed:Once(function()
			bill:Destroy()
		end)
	end
end

return function(props: Props)
	local host = React.useRef(nil :: Frame?)

	React.useEffect(function()
		local connection = props.awarded:Connect(function()
			local frame = host.current
			if frame then
				fly(frame, props.target)
			end
		end)
		return function()
			connection:Disconnect()
		end
	end, { props.awarded, props.target } :: { any })

	-- A transparent, click-through host covering the screen. The bills live here
	-- and are destroyed by their own tweens.
	return React.createElement("Frame", {
		ref = host,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
		ZIndex = 10,
	})
end
