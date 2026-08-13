--!strict
-- ScaleLayer — the one place the whole UI tree is fitted to the player's screen.
--
-- A transparent Frame holding a single UIScale. One instance at the client root
-- scales every feature at once; a feature never mounts its own or hand-scales
-- its own numbers.
--
-- **The layer is deliberately bigger than the screen.** A UIScale doesn't just
-- shrink the offsets below it — it uniformly transforms the entire subtree about
-- its parent's AnchorPoint, `Scale`-based positions included (the same fact
-- UIShell.Frame documents when it refuses to put the enter-tween's UIScale on a
-- full-screen wrapper: it would scale "from the screen, not the child's own
-- center"). A full-screen layer at Scale 0.58 therefore collapses the whole HUD
-- into the top-left 58% of the display, corner anchors and all.
--
-- So the layer sizes itself to `1 / scale` of its parent — a *virtual canvas*
-- larger than the viewport — and the UIScale maps that canvas back down onto the
-- real screen exactly. Children lay out against the canvas, in the pixel units
-- they were authored in, and the transform lands them where they belong: a
-- bottom-right panel stays pinned to the bottom-right corner, just smaller, with
-- its margin shrunk to match.
--
-- Structure-only, like Stack/Row/Grid/Slot: no visuals, not skin-resolved.
--
-- The one thing this changes for feature code: inside the layer, offsets are in
-- *scaled* units, not screen pixels. A screen-pixel measurement taken from
-- outside (`AbsolutePosition` read by a different ScreenGui, a raw input
-- coordinate) has to be divided by `ui.useViewportScale()` before it can be used
-- as an offset in here. Ratios of two absolutes (SteerStick's deflection) are
-- scale-free and need nothing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

local useViewportScale = require(script.Parent.useViewportScale)

-- Divide-by-zero guard for the `scale` override only. The real viewport scale is
-- already clamped to a much higher floor in useViewportScale.
local SCALE_FLOOR = 0.05

export type ScaleLayerProps = {
	-- Override the computed viewport scale. For stories and previews — in game
	-- leave it unset so the layer reads the real viewport.
	scale: number?,
	children: { [string]: any }?,
}

return function(props: ScaleLayerProps)
	local viewportScale = useViewportScale()
	-- Floored rather than trusted: `scale` is a story/preview override, and a 0
	-- would make the canvas infinite.
	local scale = math.max(props.scale or viewportScale, SCALE_FLOOR)

	local children: { [string]: any } = {
		Scale = React.createElement("UIScale", { Scale = scale }),
	}
	if props.children then
		for key, child in props.children do
			children[key] = child
		end
	end

	return React.createElement("Frame", {
		Name = "ScaleLayer",
		-- The virtual canvas: `1 / scale` of the parent, so the UIScale below
		-- renders it back at exactly the parent's size. Anchored at the default
		-- top-left (0, 0) because that's the transform's origin — move the anchor
		-- and the canvas stops lining up with the screen.
		Size = UDim2.fromScale(1 / scale, 1 / scale),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, children)
end
