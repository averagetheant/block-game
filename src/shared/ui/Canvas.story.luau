--!nonstrict
-- UI Labs story for the responsive canvas. Pick a device and the story draws a
-- frame that size, with a miniature HUD rendered inside a Canvas told to pretend
-- that's the screen — so what you see is what that device gets, at true size.
--
-- The device frame is drawn at its real pixel size, so Desktop won't fit in the
-- preview pane on most monitors. Phone and Tablet are the ones worth looking at;
-- Desktop is there as the reference the design pixels are authored against.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local UILabs = require(ReplicatedStorage.Packages.UILabs)
local ui = require(ReplicatedStorage.Shared.ui)

local DEVICES: { [string]: Vector2 } = {
	["Desktop 1920×1080"] = Vector2.new(1920, 1080),
	["Laptop 1366×768"] = Vector2.new(1366, 768),
	["Tablet 1180×820"] = Vector2.new(1180, 820),
	["Phone landscape 930×430"] = Vector2.new(930, 430),
	["Phone portrait 430×930"] = Vector2.new(430, 930),
}

local ORDER = {
	"Desktop 1920×1080",
	"Laptop 1366×768",
	"Tablet 1180×820",
	"Phone landscape 930×430",
	"Phone portrait 430×930",
}

-- A stand-in for the real client tree: the same shapes at the same design sizes
-- the HUD uses, so the story shows how much of the screen they actually take.
local function MockScreen(props: { readout: string })
	return React.createElement("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, {
		-- Top-centre stats strip, as TowerHUD lays it out.
		Stats = React.createElement(ui.Panel, {
			size = UDim2.fromOffset(420, 62),
			position = UDim2.new(0.5, 0, 0, 10),
			anchorPoint = Vector2.new(0.5, 0),
		}, {
			Label = React.createElement(ui.Text, {
				text = props.readout,
				textSize = 30,
				weight = Enum.FontWeight.Heavy,
				shadow = true,
				xAlignment = Enum.TextXAlignment.Center,
				size = UDim2.fromScale(1, 1),
			}),
		}),

		-- A default-sized Window, the largest surface the kit authors. The canvas
		-- is floored so this always fits, on every device above.
		Window = React.createElement(ui.Panel, {
			size = UDim2.fromOffset(820, 600),
			position = UDim2.fromScale(0.5, 0.5),
			anchorPoint = Vector2.new(0.5, 0.5),
		}, {
			Label = React.createElement(ui.Text, {
				text = "820 × 600 window",
				textSize = 44,
				shadow = true,
				xAlignment = Enum.TextXAlignment.Center,
				size = UDim2.fromScale(1, 1),
			}),
		}),

		-- Left rail: five 72px items, the Sidebar's default.
		Rail = React.createElement(ui.Stack, {
			gap = 12,
			size = UDim2.fromOffset(72, 72 * 5 + 12 * 4),
			position = UDim2.new(0, 20, 0.5, 0),
			anchorPoint = Vector2.new(0, 0.5),
		}, {
			A = React.createElement(ui.Panel, { size = UDim2.fromOffset(72, 72), layoutOrder = 1 }),
			B = React.createElement(ui.Panel, { size = UDim2.fromOffset(72, 72), layoutOrder = 2 }),
			C = React.createElement(ui.Panel, { size = UDim2.fromOffset(72, 72), layoutOrder = 3 }),
			D = React.createElement(ui.Panel, { size = UDim2.fromOffset(72, 72), layoutOrder = 4 }),
			E = React.createElement(ui.Panel, { size = UDim2.fromOffset(72, 72), layoutOrder = 5 }),
		}),

		-- Bottom-centre touch controls.
		Controls = React.createElement(ui.Row, {
			gap = 24,
			size = UDim2.fromOffset(578, 88),
			position = UDim2.new(0.5, 0, 1, -20),
			anchorPoint = Vector2.new(0.5, 1),
		}, {
			Stick = React.createElement(ui.Panel, { size = UDim2.fromOffset(260, 74), layoutOrder = 1 }),
			Turn = React.createElement(ui.Button, {
				variant = "purple",
				text = "TURN",
				size = UDim2.fromOffset(110, 88),
				layoutOrder = 2,
			}),
			Drop = React.createElement(ui.Button, {
				variant = "red",
				text = "DROP",
				size = UDim2.fromOffset(160, 88),
				layoutOrder = 3,
			}),
		}),
	})
end

return {
	summary = "Responsive canvas. Pick a device: the frame is that device's real pixel size, and everything inside is drawn in design pixels through one UIScale.",
	react = React,
	reactRoblox = ReactRoblox,

	controls = {
		device = UILabs.Choose(ORDER),
	},

	story = function(props)
		local viewport = DEVICES[props.controls.device] or DEVICES["Desktop 1920×1080"]
		local scale = ui.Responsive.scaleFor(viewport)
		local canvas = viewport / scale
		local readout = string.format(
			"%d×%d  →  ×%.2f  (%d×%d design)",
			viewport.X,
			viewport.Y,
			scale,
			math.round(canvas.X),
			math.round(canvas.Y)
		)

		-- The device frame. Bordered so the screen edge is visible against the
		-- plugin's own background — everything inside is what that screen shows.
		return React.createElement("Frame", {
			Size = UDim2.fromOffset(viewport.X, viewport.Y),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.fromRGB(24, 27, 38),
			BorderSizePixel = 0,
		}, {
			Stroke = React.createElement("UIStroke", {
				Color = Color3.fromRGB(120, 130, 160),
				Thickness = 2,
			}),
			Canvas = React.createElement(ui.Canvas, { viewport = viewport }, {
				Screen = React.createElement(MockScreen, { readout = readout }),
			}),
		})
	end,
}
