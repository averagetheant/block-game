-- Sidebar — the left rail: a vertical column of icon + label entries, and the
-- UIShell frames they open.
--
-- The column is contributed to rather than edited: a feature declares its entry
-- in a sibling `Sidebar.luau` (auto-discovered below) or, when the click needs
-- client-only code, from its own `*Presentation.client.luau`. See Registry.luau.
--
-- See docs/game/Sidebar.md for the full API and wiring examples.

local Sidebar = {}

Sidebar.Constants = require(script.Constants)
Sidebar.Registry = require(script.Registry)
Sidebar.UI = require(script.Sidebar)
Sidebar.Item = require(script.SidebarItem)
Sidebar.Rail = require(script.SidebarRail)

Sidebar.registerEntry = Sidebar.Registry.registerEntry

------------------------------------------------------------------------------
-- Auto-discovery
------------------------------------------------------------------------------
-- Walk the Features tree and require any sibling feature's `Sidebar.luau`,
-- which returns `function(Sidebar) … end` and uses `registerEntry` to declare
-- its rail entries. Same convention as PlayerData / Settings: the registering
-- module never requires Features.Sidebar itself (that would be circular), it
-- receives this table as an argument.
do
	local Features = script.Parent
	for _, featureModule in Features:GetChildren() do
		if featureModule == script then
			continue
		end
		local mod = featureModule:FindFirstChild("Sidebar")
		if mod == nil or not mod:IsA("ModuleScript") then
			continue
		end

		local ok, result = pcall(require, mod)
		if not ok then
			warn(`[Sidebar] failed to require {mod:GetFullName()}: {result}`)
			continue
		end
		if typeof(result) ~= "function" then
			warn(`[Sidebar] {mod:GetFullName()} must return function(Sidebar); got {typeof(result)}`)
			continue
		end

		local okCall, err = pcall(result, Sidebar)
		if not okCall then
			warn(`[Sidebar] registration error in {mod:GetFullName()}: {err}`)
		end
	end
end

return Sidebar
