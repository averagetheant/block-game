-- Reactions' slice of the PlayerData profile template. Discovered by
-- src/features/PlayerData/init.luau at load time; see docs/game/PlayerData.md.
--
-- Keep this to registration only — ReactionsService owns the reads and writes.
--
-- Ownership isn't here: which packs a player has bought lives in the Store's
-- slice. This is only what they've put *in the bar*, which is a different
-- question and stays true even if a pack is later refunded.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Catalog = require(ReplicatedStorage.Features.Reactions.Catalog)

return function(PlayerData)
	PlayerData.registerTemplate("Reactions", {
		-- Reaction ids, one per bar slot, in bar order.
		Slots = table.clone(Catalog.DEFAULT_SLOTS),
	})
end
