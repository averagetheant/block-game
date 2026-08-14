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
--
-- Styling is composed, not drawn: the track is `ui.Panel`'s dark-glass surface
-- (the same one the gem ProgressBar sits in) and the knob is `ui.Panel`'s gem
-- mode — noise, fill gradient, glow and shine, exactly what a gem Button's face
-- is made of. Nothing here paints a colour of its own, so the stick follows the
-- active skin along with every other primitive.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local React = require(ReplicatedStorage.Packages.React)
local ui = require(ReplicatedStorage.Shared.Boil).ui
local Constants = require(script.Parent.Constants)

local theme = ui.theme

-- Matches the gem Button's disabled wash, so a greyed stick reads as the same
-- kind of "not now" as the greyed TURN / DROP buttons beside it.
local DISABLED_OVERLAY_TRANSPARENCY = 0.45

export type Props = {
	-- Fires with the deflection, -1 (full left) to 1 (full right). Called with 0
	-- exactly once when the thumb lifts.
	onSteer: (value: number) -> (),
	-- Gem palette for the knob. Defaults to Constants.STICK_KNOB_VARIANT.
	variant: string?,
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

	-- The knob sits inside the track's stroke, not against it: a gem surface
	-- placed at the bare padding crowds the outline it's sitting in. Derived at
	-- render from the tokens so a live theme edit re-inserts it.
	local knobInset = theme.padding + theme.strokeThickness
	local knobSize = Constants.STICK_TRACK_HEIGHT - knobInset * 2

	local half = Constants.STICK_TRACK_WIDTH / 2 - knobSize / 2

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

	-- Same shape as a gem Button: the visuals are inert and one invisible
	-- Trigger on top owns the input. The outer Frame is what gets measured, so
	-- `steerFrom` reads the track's true bounds however the HUD places it.
	return React.createElement("Frame", {
		ref = trackRef,
		Size = UDim2.fromOffset(Constants.STICK_TRACK_WIDTH, Constants.STICK_TRACK_HEIGHT),
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		LayoutOrder = props.layoutOrder,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, {
		Track = React.createElement(ui.Panel, {
			size = UDim2.fromScale(1, 1),
			transparency = if props.disabled
				then Constants.STICK_TRACK_DISABLED_TRANSPARENCY
				else Constants.STICK_TRACK_TRANSPARENCY,
			zIndex = 1,
		}),

		-- A transparent positioner: the gem surface inside it fills the frame,
		-- and the drag moves the frame. Keeping the two apart means the imperative
		-- Position write never touches the skinned content.
		Knob = React.createElement("Frame", {
			ref = knobRef,
			Size = UDim2.fromOffset(knobSize, knobSize),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 2,
		}, {
			Gem = React.createElement(ui.Panel, {
				variant = props.variant or Constants.STICK_KNOB_VARIANT,
				hasShine = true,
				-- The badge tile, not the button one: the noise has to read at
				-- knob scale, and the full-size tile barely repeats across 60px.
				tileSize = theme.badgeTileSize,
				size = UDim2.fromScale(1, 1),
			}),
		}),

		DisabledOverlay = if props.disabled
			then React.createElement("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Color3.fromRGB(0, 0, 0),
				BackgroundTransparency = DISABLED_OVERLAY_TRANSPARENCY,
				BorderSizePixel = 0,
				ZIndex = 3,
			})
			else nil,

		Trigger = React.createElement("TextButton", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Active = not props.disabled,
			Text = "",
			ZIndex = 10,
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
		}),
	})
end
