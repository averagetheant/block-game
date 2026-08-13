--!strict
-- How the framework maps its *design pixels* onto a real screen — a 4K monitor,
-- a laptop window, a phone held sideways.
--
-- Every size in this codebase (theme tokens, feature layout constants, the
-- offsets inside a component) is written against a 1920×1080 screen. Nothing
-- reads the viewport at its call site, and nothing should: `Canvas` renders the
-- whole client tree through one UIScale computed here, so a phone's ~930×430
-- viewport stops being handed a HUD authored for a monitor. That mismatch is
-- exactly what "the UI doesn't scale on mobile" looks like — everything roughly
-- twice too big, panels overlapping each other, the rail running off-screen.
--
-- The scale is deliberately NOT a straight ratio. Scaling everything by
-- viewport/reference preserves the proportions and produces 12px text on a
-- phone: a physically smaller screen needs a proportionally *larger* UI, not the
-- same one shrunk. Taking the square root of the ratio splits that difference —
-- the layout shrinks enough to fit, while text stays readable and touch targets
-- stay tappable.
--
--   3840×2160  →  1.41
--   1920×1080  →  1.00   ← the reference; the UI renders exactly as authored
--   1280×720   →  0.82
--    930×430   →  0.63   phone, landscape
--
-- Two hard caps sit on top of that curve:
--
--   * MIN_CANVAS — the design canvas never gets smaller than this, so the largest
--     surface the kit authors (an 820×600 Window) always fits on screen. This is
--     what binds on a portrait phone, where the sqrt curve alone would leave the
--     canvas narrower than a window.
--   * MIN_SCALE / MAX_SCALE — bounds for viewports that aren't really viewports
--     (a 1×1 camera during boot) or are far past anything authored for.
--
-- Insets are the other half of "correct on mobile": the Roblox topbar, a notch,
-- and the home indicator all sit *inside* BoilRoot's bounds (it's a full-bleed
-- ScreenGui, ScreenInsets = None), so edge-anchored UI has to move in past them.
-- `useViewport().insets` reports how far, already converted to design pixels.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local React = require(ReplicatedStorage.Packages.React)

local Responsive = {}

-- The screen the UI is authored against. Height is what drives the curve: UI
-- density tracks how tall the screen is, and every aspect ratio from 4:3 to a
-- phone's 2.2:1 has more width to spare than height.
Responsive.REFERENCE_HEIGHT = 1080

-- The smallest design canvas the scale is allowed to produce, in design pixels.
-- Sized to hold the kit's largest surface (Sidebar's 820×600 default Window) plus
-- a margin, so no screen can be given a canvas its own windows don't fit in.
Responsive.MIN_CANVAS = Vector2.new(900, 680)

Responsive.MIN_SCALE = 0.3
Responsive.MAX_SCALE = 1.5

export type Insets = {
	top: number,
	bottom: number,
	left: number,
	right: number,
}

export type Metrics = {
	-- Real screen size in device pixels.
	viewport: Vector2,
	-- Design pixels → device pixels.
	scale: number,
	-- The design-space size of the canvas (viewport / scale). Feature code that
	-- needs to know how much room it actually has reads this, not `viewport`.
	canvas: Vector2,
	-- Chrome insets in DESIGN pixels, ready to add to an edge margin.
	insets: Insets,
}

local ZERO_INSETS: Insets = { top = 0, bottom = 0, left = 0, right = 0 }

-- The design-pixel → device-pixel factor for a viewport. Pure, so the story can
-- ask "what would a phone get?" without a phone.
function Responsive.scaleFor(viewport: Vector2): number
	-- A camera that hasn't been set up yet reports a degenerate size; scaling to
	-- it would flash the whole UI at the minimum scale for a frame.
	if viewport.X <= 1 or viewport.Y <= 1 then
		return 1
	end

	local scale = math.sqrt(viewport.Y / Responsive.REFERENCE_HEIGHT)
	-- Never leave the design canvas smaller than the biggest thing drawn on it.
	scale = math.min(scale, viewport.X / Responsive.MIN_CANVAS.X, viewport.Y / Responsive.MIN_CANVAS.Y)
	return math.clamp(scale, Responsive.MIN_SCALE, Responsive.MAX_SCALE)
end

local function readViewport(): Vector2
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return Vector2.new(1920, Responsive.REFERENCE_HEIGHT)
	end
	return camera.ViewportSize
end

-- GuiService reports the topbar, but nothing reports the *device's* safe area —
-- the notch and the home indicator have no API. What Roblox does expose is a
-- ScreenGui that already respects them: an empty one with
-- `ScreenInsets = DeviceSafeInsets` lays itself out inside the safe region, so
-- its AbsolutePosition/AbsoluteSize measured against the full viewport *is* the
-- inset on each side. It has no children and never draws.
--
-- Created from the hook's effect, not from a measure: rendering must not have
-- side effects, and a discarded render shouldn't leave a ScreenGui behind. Kept
-- in PlayerGui with ResetOnSpawn off, so it survives respawns like BoilRoot does.
-- Until it exists (and for the frame it takes to lay out), insets fall back to
-- the GuiService numbers.
local probe: ScreenGui? = nil

local function safeAreaProbe(): ScreenGui?
	if probe ~= nil and probe.Parent ~= nil then
		return probe
	end
	return nil
end

local function ensureSafeAreaProbe(): ScreenGui?
	local existing = safeAreaProbe()
	if existing ~= nil then
		return existing
	end

	local player = Players.LocalPlayer
	if player == nil then
		return nil
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return nil
	end

	local created = Instance.new("ScreenGui")
	created.Name = "BoilSafeArea"
	created.ResetOnSpawn = false
	created.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	created.Parent = playerGui
	probe = created
	return created
end

-- Everything the device keeps for itself, in device pixels, on each edge.
-- Guarded rather than trusted: an inset past a fifth of the screen is a
-- measurement that went wrong (a probe read mid-layout), and zero is a much
-- better failure than a HUD shoved into the middle of the screen.
local function readInsets(): Insets
	local viewport = readViewport()
	local limit = viewport * 0.2

	local topLeft = GuiService:GetGuiInset()
	local bar = GuiService.TopbarInset
	local insets = {
		-- Both describe the topbar; on a phone the unibar sits below the notch and
		-- reaches further down, on a PC GetGuiInset is the one that's set.
		top = math.max(topLeft.Y, bar.Max.Y),
		bottom = 0,
		left = math.max(topLeft.X, bar.Min.X),
		right = 0,
	}

	local device = safeAreaProbe()
	if device ~= nil and device.AbsoluteSize.X > 1 and device.AbsoluteSize.Y > 1 then
		local origin = device.AbsolutePosition
		local size = device.AbsoluteSize
		insets.top = math.max(insets.top, origin.Y)
		insets.left = math.max(insets.left, origin.X)
		insets.bottom = viewport.Y - (origin.Y + size.Y)
		insets.right = viewport.X - (origin.X + size.X)
	end

	return {
		top = math.clamp(insets.top, 0, limit.Y),
		bottom = math.clamp(insets.bottom, 0, limit.Y),
		left = math.clamp(insets.left, 0, limit.X),
		right = math.clamp(insets.right, 0, limit.X),
	}
end

-- Everything a caller needs about the screen, in one table. `override` pretends
-- the screen is some other size (the Canvas story previews a phone on a monitor);
-- with one set, insets are zeroed — the simulated screen has no real chrome.
function Responsive.metricsFor(viewport: Vector2, insets: Insets): Metrics
	local scale = Responsive.scaleFor(viewport)
	return {
		viewport = viewport,
		scale = scale,
		canvas = viewport / scale,
		insets = {
			top = insets.top / scale,
			bottom = insets.bottom / scale,
			left = insets.left / scale,
			right = insets.right / scale,
		},
	}
end

local function sameInsets(a: Insets, b: Insets): boolean
	return a.top == b.top and a.bottom == b.bottom and a.left == b.left and a.right == b.right
end

-- Live metrics, re-read whenever the screen changes: a resized window, a rotated
-- phone, a camera swapped out from under us, the topbar changing shape.
function Responsive.useViewport(override: Vector2?): Metrics
	-- `false` rather than nil for the dependency: a nil in a Luau array is a hole,
	-- so `{ override }` would change *length* the first time an override appears
	-- and React compares dependency arrays element by element.
	local overrideKey: Vector2 | boolean = override or false

	local measure = React.useCallback(function(): Metrics
		if override ~= nil then
			return Responsive.metricsFor(override, ZERO_INSETS)
		end
		return Responsive.metricsFor(readViewport(), readInsets())
	end, { overrideKey } :: { any })

	local metrics, setMetrics = React.useState(measure)

	React.useEffect(function()
		local connections: { RBXScriptConnection } = {}
		local alive = true

		local function refresh()
			if not alive then
				return
			end
			local latest = measure()
			setMetrics(function(previous: Metrics): Metrics
				-- Bail out of the update when nothing moved: ViewportSize fires on
				-- every window drag frame, and re-rendering the whole client tree
				-- for an identical value is the one cost this hook could impose.
				if previous.viewport == latest.viewport and sameInsets(previous.insets, latest.insets) then
					return previous
				end
				return latest
			end)
		end

		-- The camera itself is replaceable (respawn, a cutscene rig), so the
		-- ViewportSize subscription has to be re-bound when it changes.
		local cameraConnection: RBXScriptConnection? = nil
		local function bindCamera()
			if cameraConnection then
				cameraConnection:Disconnect()
			end
			local camera = Workspace.CurrentCamera
			if camera == nil then
				return
			end
			cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(refresh)
		end

		bindCamera()
		table.insert(
			connections,
			Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
				bindCamera()
				refresh()
			end)
		)
		table.insert(connections, GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(refresh))

		-- The safe-area probe re-lays-out a frame or two after a rotation, so the
		-- ViewportSize signal alone would read the old insets against the new
		-- screen. Bound after the first measure below, which is what creates it.
		local function bindProbe()
			-- A simulated screen has no real chrome to measure, so a story doesn't
			-- get to leave a probe in the player's PlayerGui.
			if override ~= nil then
				return
			end
			local device = ensureSafeAreaProbe()
			if device == nil then
				return
			end
			table.insert(connections, device:GetPropertyChangedSignal("AbsoluteSize"):Connect(refresh))
			table.insert(connections, device:GetPropertyChangedSignal("AbsolutePosition"):Connect(refresh))
		end

		-- The camera is usually still coming up when the tree first mounts, and the
		-- probe doesn't exist until this runs — so measure, create, then measure
		-- again once it has laid itself out.
		refresh()
		bindProbe()
		task.defer(refresh)

		return function()
			-- The deferred re-measure above can outlive the unmount by a frame.
			alive = false
			if cameraConnection then
				cameraConnection:Disconnect()
			end
			for _, connection in connections do
				connection:Disconnect()
			end
		end
	end, { measure } :: { any })

	return metrics
end

return Responsive
