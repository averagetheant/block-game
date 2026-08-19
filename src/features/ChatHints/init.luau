-- ChatHints — a tip line in the general chat channel every few minutes.
--
-- The feature ships **no tips**. It owns the clock, the channel and the
-- no-repeats rotation; every hint is declared by the feature it's about, in a
-- sibling `ChatHints.luau` this file auto-discovers — the same convention
-- PlayerData / Settings / Store / Sidebar / DailyRewards use.
--
-- See docs/game/ChatHints.md for the API and the cadence.

local ChatHints = {}

ChatHints.Constants = require(script.Constants)
ChatHints.Registry = require(script.Registry)

ChatHints.registerHint = ChatHints.Registry.registerHint
ChatHints.registerHints = ChatHints.Registry.registerHints
ChatHints.list = ChatHints.Registry.list

------------------------------------------------------------------------------
-- Auto-discovery
------------------------------------------------------------------------------
-- Walk the Features tree and require any sibling feature's `ChatHints.luau`,
-- which returns `function(ChatHints) … end` and registers that feature's tips.
-- The registering module never requires Features.ChatHints itself (that would
-- be circular) — it receives this table as an argument.
--
-- The registry is deliberately *not* sealed afterwards: the controller re-reads
-- it on every rotation, so a late registration just joins the next bag.
do
	local Features = script.Parent
	for _, featureModule in Features:GetChildren() do
		if featureModule == script then
			continue
		end
		local mod = featureModule:FindFirstChild("ChatHints")
		if mod == nil or not mod:IsA("ModuleScript") then
			continue
		end

		local ok, result = pcall(require, mod)
		if not ok then
			warn(`[ChatHints] failed to require {mod:GetFullName()}: {result}`)
			continue
		end
		if typeof(result) ~= "function" then
			warn(`[ChatHints] {mod:GetFullName()} must return function(ChatHints); got {typeof(result)}`)
			continue
		end

		local okCall, err = pcall(result, ChatHints)
		if not okCall then
			warn(`[ChatHints] registration error in {mod:GetFullName()}: {err}`)
		end
	end
end

return ChatHints
