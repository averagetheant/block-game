--!strict
-- The multiplier that maps this kit's pixel offsets onto the player's screen.
--
-- Every size in the UI is authored in pixels — theme tokens, window sizes, HUD
-- margins, TextSize, stroke thickness. Pixels are absolute, so a panel that
-- takes a third of a desktop window takes the whole width of a phone: the same
-- numbers, a screen a third the size. This hook is the single number that fixes
-- that, applied once by <ScaleLayer> at the client root.
--
-- The scale is the smaller of the two axis ratios against REFERENCE, so a layout
-- that fits the reference can't overflow either edge, and it's clamped at both
-- ends:
--   * MAX_SCALE — the reference is the *design* size, not a floor to grow from.
--     A 1440p monitor keeps the desktop look instead of inflating every panel.
--     Raise it above 1 if you'd rather the UI grow with the window.
--   * MIN_SCALE — the point where text stops being readable and touch targets
--     stop being reliably hittable. A screen narrower than half the reference
--     gets a UI that's a bit too big rather than one that can't be used.
--
-- Read it directly (`ui.useViewportScale()`) only when a feature needs the
-- number itself — e.g. converting a real screen-pixel measurement (an
-- AbsolutePosition) into the scaled tree's coordinate space. Ordinary UI needs
-- nothing: it's already inside the ScaleLayer.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local React = require(ReplicatedStorage.Packages.React)

-- The viewport every pixel offset in the kit is authored against: 720p, the
-- smallest screen the UI is meant to look "native" on. Change this and the whole
-- UI re-scales on every device at once.
local REFERENCE = Vector2.new(1280, 720)
local MIN_SCALE = 0.5
local MAX_SCALE = 1

local function scaleFor(viewport: Vector2): number
	local ratio = math.min(viewport.X / REFERENCE.X, viewport.Y / REFERENCE.Y)
	return math.clamp(ratio, MIN_SCALE, MAX_SCALE)
end

local function currentScale(): number
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return scaleFor(REFERENCE)
	end
	return scaleFor(camera.ViewportSize)
end

local function useViewportScale(): number
	local scale, setScale = React.useState(currentScale)

	React.useEffect(function()
		local viewportConn: RBXScriptConnection? = nil

		-- Roblox swaps CurrentCamera out from under you (respawns, cutscenes),
		-- and the replaced camera's ViewportSize stops tracking the window — so
		-- the listener is rebound to whichever camera is current, not connected
		-- once at mount.
		local function bind()
			if viewportConn then
				viewportConn:Disconnect()
				viewportConn = nil
			end
			local camera = Workspace.CurrentCamera
			if camera == nil then
				return
			end
			setScale(scaleFor(camera.ViewportSize))
			viewportConn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				setScale(scaleFor(camera.ViewportSize))
			end)
		end

		local cameraConn = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bind)
		bind()

		return function()
			cameraConn:Disconnect()
			if viewportConn then
				viewportConn:Disconnect()
			end
		end
	end, {})

	return scale
end

return useViewportScale
