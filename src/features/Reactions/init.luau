-- Reactions — the white bar along the bottom of the screen, and the emojis it
-- throws up everyone's screen.
--
-- See docs/game/Reactions.md for the catalog, the packets and the Studio assets
-- (there are none — every default reaction is a glyph).

local Reactions = {}

Reactions.Constants = require(script.Constants)
Reactions.Catalog = require(script.Catalog)
Reactions.Bar = require(script.ReactionBar)
Reactions.Float = require(script.ReactionFloat)
Reactions.Glyph = require(script.ReactionGlyph)
Reactions.Inventory = require(script.ReactionInventory)

return Reactions
