--!strict
-- The world's reaction to a frame being open: the background blurs and the
-- camera zooms in slightly, so the window reads as *in front of* the game
-- rather than painted onto it.
--
-- Mounted once by FrameProvider, so it covers every frame automatically —
-- features don't opt in, and a new frame gets the effect for free.
--
-- It renders nothing. Both halves are instance-level tweens (a BlurEffect it
-- owns in Lighting, and the camera's FieldOfView) rather than React state:
-- neither is a GUI, and re-rendering the tree 60 times a frame to move a blur
-- would be absurd.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local React = require(ReplicatedStorage.Packages.React)
local Constants = require(script.Parent.Constants)

-- Named so it's obvious in the explorer where a stray blur came from, and so a
-- hot-reload finds the existing one instead of stacking a second.
local BLUR_NAME = "UIShellFocusBlur"

export type Props = {
	-- Whether any frame is open. Passed in rather than read from useFrame() so
	-- this module doesn't require FrameProvider (which mounts it — that would be
	-- a require cycle), and so the story can drive it from a toggle.
	isOpen: boolean,
}

return function(props: Props)
	local isOpen = props.isOpen

	-- The camera's FOV *before* we touched it. Captured on the closed → open
	-- edge and held until we've put it back, so switching straight from one
	-- frame to another can't capture the already-zoomed value and ratchet the
	-- FOV down a little further every time.
	local baseFov = React.useRef(nil :: number?)

	local blur = React.useRef(nil :: BlurEffect?)
	React.useEffect(function()
		local existing = Lighting:FindFirstChild(BLUR_NAME)
		if existing then
			existing:Destroy()
		end

		local effect = Instance.new("BlurEffect")
		effect.Name = BLUR_NAME
		effect.Size = 0
		effect.Enabled = true
		effect.Parent = Lighting
		blur.current = effect

		return function()
			blur.current = nil
			effect:Destroy()
		end
	end, {})

	React.useEffect(function()
		local camera = workspace.CurrentCamera
		if isOpen and baseFov.current == nil and camera then
			baseFov.current = camera.FieldOfView
		end

		local tweens: { Tween } = {}

		local effect = blur.current
		if effect then
			table.insert(
				tweens,
				TweenService:Create(effect, Constants.FOCUS_TWEEN_INFO, {
					Size = if isOpen then Constants.FOCUS_BLUR_SIZE else 0,
				})
			)
		end

		-- A lower FOV is a *narrower* view, i.e. a zoom in.
		local from = baseFov.current
		if camera and from ~= nil then
			table.insert(
				tweens,
				TweenService:Create(camera, Constants.FOCUS_TWEEN_INFO, {
					FieldOfView = if isOpen then from - Constants.FOCUS_FOV_ZOOM else from,
				})
			)
		end

		for _, tween in tweens do
			tween:Play()
		end

		-- Only forget the base once the camera is actually back on it; letting go
		-- earlier would re-capture mid-tween on a fast open/close/open.
		if not isOpen then
			task.delay(Constants.FOCUS_TWEEN_INFO.Time, function()
				baseFov.current = nil
			end)
		end

		return function()
			for _, tween in tweens do
				tween:Cancel()
				tween:Destroy()
			end
		end
	end, { isOpen } :: { any })

	-- Restore on unmount: the tree can go away (a respawn, a hot reload) with a
	-- frame still open, and a permanently blurred, permanently zoomed game is a
	-- nasty thing to leave behind.
	React.useEffect(function()
		return function()
			local camera = workspace.CurrentCamera
			if camera and baseFov.current ~= nil then
				camera.FieldOfView = baseFov.current
			end
		end
	end, {})

	return nil
end
