--!strict
-- Sidebar layout defaults. Override at the call site via props per item or
-- per Sidebar instance; bump these to change the framework-wide defaults.
--
-- Shared visual tokens (e.g. the label stroke thickness) come from
-- `Shared.ui.theme` so they track the rest of the gem-styled UI.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local theme = require(ReplicatedStorage.Shared.Boil).ui.theme

return {
	-- SidebarItem square size (pixels). The whole item is one icon — the
	-- label rides on top of it, anchored to the bottom edge.
	DEFAULT_ICON_SIZE = 72,
	-- Label TextSize (pixels). On the shared ladder's body tier — these are
	-- navigation labels, and a phone halves every pixel here (see
	-- `useViewportScale`), so anything below this stops being readable.
	DEFAULT_LABEL_SIZE = theme.textSizeRegular,
	-- Miter UIStroke thickness on the label. Matches the gem text outline
	-- minus the offset shadow layer — readable on top of any icon.
	LABEL_STROKE_THICKNESS = theme.thinStrokeThickness,
	-- Distance (pixels) from the bottom edge of the icon to the baseline of
	-- the label. 0 sits the label flush with the icon's bottom edge — still
	-- inside its visual bounds, since the art doesn't reach the edge.
	LABEL_BOTTOM_INSET = 0,
	-- Rotation tilt picked at random on hover-enter (degrees). Magnitude
	-- comes from [MIN, MAX]; sign is 50/50. Set MAX = 0 to disable.
	HOVER_TILT_MIN_DEG = 4,
	HOVER_TILT_MAX_DEG = 12,
	-- Vertical gap between sibling SidebarItems in the column (pixels).
	ITEM_SPACING = 12,
	-- Default outer Sidebar padding on each side (pixels).
	PADDING = 12,

	-- ------------------------------------------------------------------ rail --
	-- Gap between the "menu" cluster and the "actions" cluster. Wider than
	-- ITEM_SPACING on purpose: it's what tells the player that Nuke is a
	-- different sort of thing from Shop, without drawing a divider.
	GROUP_GAP = 28,
	-- Distance from the screen's left edge to the rail (pixels).
	RAIL_MARGIN = 20,
	-- Default size of the Window a rail entry opens. Large content surfaces
	-- (a shop grid, an inventory) are the reason the rail is off-center at all,
	-- so this is deliberately roomy — override per entry with `windowSize`.
	WINDOW_SIZE = UDim2.fromOffset(820, 600),

	-- Which surfaces this feature renders. `root` is the rail itself; turn it
	-- off and every registered entry goes away with it, code intact.
	Presentations = {
		root = true,
	},
}
