-- Shared constants for the Settings feature.

return {
	-- Key in the player's profile that holds the map of settingId → value.
	-- Registered into the PlayerData profile template by src/features/Settings/PlayerData.luau.
	-- Read by the client + server, written by PlayerDataService.SetValue
	-- routed from SettingsService.
	PROFILE_KEY = "Settings",

	-- The UIShell frame id the Settings window opens on. Lives here rather than
	-- only on the feature table so the shared discovery files (Sidebar.luau) can
	-- name it without requiring `Features.Settings` — that init pulls in the React
	-- UI, which the server has no use for. `Settings.FRAME_ID` re-exports it.
	FRAME_ID = "Settings",

	-- Defensive cap on inbound packet ids (the client is the source of these,
	-- so we don't trust their length).
	MAX_SETTING_ID_LENGTH = 128,

	-- How long the highlighted row lingers after Settings.linkTo(id) before
	-- the focus state clears on its own.
	LINK_HIGHLIGHT_SECONDS = 1.6,

	-- Which presentations are active. Settings ships a screen (HUD window) and a
	-- world surface: parts tagged `SettingsToggleStation` whose ProximityPrompt
	-- flips the setting named by the part's `SettingId` attribute.
	Presentations = {
		screen = true,
		world = true,
		-- The left-rail entry that opens the window. Off = Settings is still
		-- reachable (the world station, `Settings.linkTo`) but has no icon.
		sidebar = true,
		-- The native Roblox topbar icon (TopbarPlus). Off = the topbar is left
		-- untouched; the rail entry and the world station still reach Settings.
		-- Redundant with `sidebar` on purpose — pick one, or run both.
		topbar = true,
	},

	-- Native-topbar icon (TopbarPlus). Drawn by Roblox's own topbar, outside the
	-- React tree and outside ScaleLayer, so none of the shared theme / 1280×720
	-- pixel rules reach it — TopbarPlus sizes itself against the real topbar and
	-- handles mobile + gamepad on its own. The image is `assets.Icons.settings`,
	-- the same one the rail entry uses.
	--
	-- Where the icon sits on the topbar (TopbarPlus sorts left-aligned icons by
	-- this, low → high). 2 puts Settings after DailyRewards, which claims 1.
	TOPBAR_ORDER = 2,
	-- Hover / controller caption. Empty string = no caption.
	TOPBAR_CAPTION = "Settings",

	-- CollectionService tag a part must carry to become a Settings toggle
	-- station, plus the attribute that names which setting it flips.
	WORLD_TAG = "SettingsToggleStation",
	WORLD_SETTING_ATTRIBUTE = "SettingId",
}
