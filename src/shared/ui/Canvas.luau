--!strict
-- The design-space canvas — one full-screen Frame that every client UI lives
-- inside, drawn through a single UIScale (see Responsive for the scale itself).
--
-- The mechanism is the inverse size: a Frame sized `1 / scale` of the screen and
-- then scaled by `scale` renders exactly full-screen, but its own coordinate
-- space is `viewport / scale` design pixels across. So scale-based positions are
-- untouched — `UDim2.fromScale(0.5, 0.5)` is still screen centre — while every
-- *offset* below it is a design pixel that shrinks with the screen. Nothing in
-- the tree underneath has to know the screen size, which is what keeps feature
-- code free of `ViewportSize` maths.
--
-- Anchored top-left on purpose: UIScale scales about the object's anchor point,
-- so (0, 0) is what lands the scaled frame flush with the viewport.
--
-- Mounted once, by the client entry, around the registered roots. A feature
-- never mounts its own — nesting canvases would scale twice.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Responsive = require(script.Parent.Responsive)

export type Props = {
	-- Pretend the screen is this size instead of measuring it. Stories and dev
	-- tools only — in game the canvas measures the real viewport.
	viewport: Vector2?,
	children: { [string]: any }?,
}

return function(props: Props)
	local metrics = Responsive.useViewport(props.viewport)

	local children: { [string]: any } = {}
	for key, child in props.children or {} do
		children[key] = child
	end
	-- Assigned after the copy: the scale is the one child the canvas must have,
	-- so a registered root keyed the same way can't displace it.
	children.CanvasScale = React.createElement("UIScale", { Scale = metrics.scale })

	return React.createElement("Frame", {
		Size = UDim2.fromScale(1 / metrics.scale, 1 / metrics.scale),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, children)
end
