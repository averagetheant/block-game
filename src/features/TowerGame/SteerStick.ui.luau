--!strict
-- The touch steering control: a horizontal track with a knob you drag left and
-- right. One axis, because the game is one axis — a round two-axis stick would
-- promise vertical control the piece doesn't have.
--
-- Reports a **continuous** value in [-1, 1] rather than a direction, which is
-- what the old LEFT/RIGHT buttons couldn't do: `setSteer` is analog now, so a
-- small drag nudges the piece and a full one moves it at `STEER_SPEED`. Holding
-- a position keeps steering — there's no repeat-tapping.
--
-- Self-centring: letting go returns the knob and reports 0. A stick that stayed
-- where you left it would keep the piece sliding after your thumb was gone.
--
-- The knob is driven imperatively from the input events, not from React state.
-- A dragged control updates every frame it moves, and routing that through state
-- would re-render the whole HUD for the length of the drag.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local React = require(ReplicatedStorage.Packages.React)
local ui = require(ReplicatedStorage.Shared.Boil).ui
local Constants = require(script.Parent.Constants)

local theme = ui.theme

export type Props = {
	-- Fires with the deflection, -1 (full left) to 1 (full right). Called with 0
	-- exactly once when the thumb lifts.
	onSteer: (value: number) -> (),
	disabled: boolean?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
}

return function(props: Props)
	local trackRef = React.useRef(nil :: Frame?)
	local knobRef = React.useRef(nil :: Frame?)
	-- The active touch. Held in a ref rather than state because it changes on
	-- every drag event and nothing renders from it.
	local dragging = React.useRef(false)
	-- The exact InputObject that started the drag, so the service-level hooks
	-- below can tell this gesture from any other finger on the screen.
	local tracked = React.useRef(nil :: InputObject?)

	local half = Constants.STICK_TRACK_WIDTH / 2 - Constants.STICK_KNOB_SIZE / 2

	-- The knob follows the finger *past* the end of the track, up to
	-- STICK_OVERREACH. Pinning it hard at the edge is what read as a snap: the
	-- knob stopped dead under a thumb that was still moving, so the control
	-- looked like it had let go. It keeps travelling instead — the steering is
	-- already at full by then, and the knob's job past that point is only to
	-- show that the stick is still held.
	local moveKnob = React.useCallback(function(raw: number)
		local knob = knobRef.current
		if knob == nil then
			return
		end
		local travel = math.clamp(raw, -Constants.STICK_OVERREACH, Constants.STICK_OVERREACH)
		knob.Position = UDim2.new(0.5, travel * half, 0.5, 0)
	end, { half })

	-- Screen X → deflection, **unclamped**. The caller clamps for the steer value
	-- and lets the knob use the raw one, so the two can disagree past the edge:
	-- speed saturates at 1, travel keeps going.
	--
	-- Measured against the track's own absolute position so it stays correct
	-- wherever the HUD puts the control, on any screen size.
	local steerFrom = React.useCallback(function(screenX: number): number
		local track = trackRef.current
		if track == nil then
			return 0
		end
		local centre = track.AbsolutePosition.X + track.AbsoluteSize.X / 2
		local reach = track.AbsoluteSize.X / 2
		if reach <= 0 then
			return 0
		end
		return (screenX - centre) / reach
	end, {})

	local release = React.useCallback(function()
		if not dragging.current then
			return
		end
		dragging.current = false
		moveKnob(0)
		props.onSteer(0)
	end, { moveKnob, props.onSteer } :: { any })

	local update = React.useCallback(function(screenX: number)
		local raw = steerFrom(screenX)
		-- Knob takes the raw value (so it keeps moving past the edge), steering
		-- takes the clamped one (so speed tops out at STEER_SPEED).
		moveKnob(raw)
		props.onSteer(math.clamp(raw, -1, 1))
	end, { steerFrom, moveKnob, props.onSteer } :: { any })

	-- A disabled stick must not keep steering from wherever it was left: it isn't
	-- unmounted between turns, only greyed out.
	React.useEffect(function()
		if props.disabled then
			release()
		end
	end, { props.disabled, release } :: { any })

	-- The drag is tracked on UserInputService, not on the track, because a thumb
	-- that slides off the control still owns the gesture until it lifts. Bound to
	-- the frame's own events, movement stopped the instant the finger crossed the
	-- edge — which on a small control is most of the time, and felt like the
	-- stick dropping out from under you.
	--
	-- `InputObject` identity is what ties the move and the end back to the touch
	-- that started it, so a second finger elsewhere can't steal or end this drag.
	React.useEffect(function()
		local moved = UserInputService.InputChanged:Connect(function(input: InputObject)
			if input ~= tracked.current then
				return
			end
			update(input.Position.X)
		end)

		local ended = UserInputService.InputEnded:Connect(function(input: InputObject)
			if input ~= tracked.current then
				return
			end
			tracked.current = nil
			release()
		end)

		return function()
			moved:Disconnect()
			ended:Disconnect()
		end
	end, { update, release } :: { any })

	return React.createElement("TextButton", {
		ref = trackRef,
		Size = UDim2.fromOffset(Constants.STICK_TRACK_WIDTH, Constants.STICK_TRACK_HEIGHT),
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		LayoutOrder = props.layoutOrder,
		BackgroundColor3 = Constants.STICK_TRACK_COLOR,
		BackgroundTransparency = if props.disabled then 0.75 else 0.45,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Active = not props.disabled,
		Text = "",
		[React.Event.InputBegan] = function(_, input: InputObject)
			if props.disabled then
				return
			end
			if
				input.UserInputType ~= Enum.UserInputType.Touch
				and input.UserInputType ~= Enum.UserInputType.MouseButton1
			then
				return
			end
			dragging.current = true
			-- Remembered so the service-level move/end hooks can recognise this
			-- finger after it has left the control.
			tracked.current = input
			update(input.Position.X)
		end,
	}, {
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(0, Constants.STICK_TRACK_HEIGHT / 2),
		}),
		Stroke = React.createElement("UIStroke", {
			Color = Constants.STICK_STROKE_COLOR,
			Thickness = theme.strokeThickness,
			Transparency = if props.disabled then 0.7 else 0.35,
		}),

		Knob = React.createElement("Frame", {
			ref = knobRef,
			Size = UDim2.fromOffset(Constants.STICK_KNOB_SIZE, Constants.STICK_KNOB_SIZE),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Constants.STICK_KNOB_COLOR,
			BackgroundTransparency = if props.disabled then 0.5 else 0,
			BorderSizePixel = 0,
			-- The track owns the input; a knob that took its own would swallow
			-- the drag the moment the thumb landed on it.
			Active = false,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
			Stroke = React.createElement("UIStroke", {
				Color = Constants.STICK_STROKE_COLOR,
				Thickness = theme.strokeThickness,
				Transparency = 0.2,
			}),
		}),
	})
end
