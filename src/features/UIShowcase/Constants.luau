-- Shared config for UIShowcase.
--
-- UIShowcase is Boil's demo HUD — the left sidebar (Inventory / Shop / Notes /
-- Settings) and the window frames those entries open. TowerGame draws its own
-- full-screen HUD and wants the screen clear, so the surface is switched off
-- here rather than deleted: the stories still work in UI Labs, and flipping the
-- flag brings the sidebar back.
--
-- Note this also takes the Notes and Settings *windows* out of reach, since
-- those mount into this HUD's frame slots.

return {
	Presentations = {
		screen = false,
	},
}
