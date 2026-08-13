-- Shared packet definitions for Cursors. Both realms require this module.
--
-- Both directions are unreliable on purpose. A cursor position is only true for
-- the instant it was sampled — a dropped one is replaced by the next report a
-- twelfth of a second later, and re-sending a stale position would be worse than
-- losing it. Nothing here is an intent, so nothing here needs delivery.
--
-- The colour never travels: both ends derive it from the user id (see
-- Palette.luau), so a cursor's colour costs no bytes and can't disagree between
-- clients.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ByteNet = require(ReplicatedStorage.Packages.ByteNet)

return ByteNet.defineNamespace("Cursors", function()
	return {
		-- Client → Server: my cursor is here on the play plane. Sending nothing
		-- is how a client says "I have no cursor right now" — the server times
		-- it out rather than needing a separate goodbye packet.
		Move = ByteNet.definePacket({
			value = ByteNet.struct({
				x = ByteNet.float32,
				y = ByteNet.float32,
			}),
			reliabilityType = "unreliable",
		}),

		-- Server → All: every live cursor, as one list. A whole-list packet
		-- rather than per-player deltas because it's a handful of floats and a
		-- full list can't get out of step with itself — a client that misses a
		-- "player left" delta would otherwise keep drawing a ghost.
		State = ByteNet.definePacket({
			value = ByteNet.struct({
				cursors = ByteNet.array(ByteNet.struct({
					userId = ByteNet.float64,
					x = ByteNet.float32,
					y = ByteNet.float32,
				})),
			}),
			reliabilityType = "unreliable",
		}),
	}
end)
