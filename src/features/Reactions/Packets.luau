-- Shared packet definitions for Reactions. Both realms require this module.
--
-- A reaction is a broadcast, so it goes up as an id and comes back down to
-- everyone as an id plus who sent it. The glyph itself never travels — both
-- ends look it up in the shared Catalog, which is what stops a client from
-- inventing a reaction nobody else can render (or one nobody bought).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ByteNet = require(ReplicatedStorage.Packages.ByteNet)

return ByteNet.defineNamespace("Reactions", function()
	return {
		-- Client → Server: play this reaction for the room.
		Send = ByteNet.definePacket({
			value = ByteNet.struct({
				reactionId = ByteNet.string,
			}),
			reliabilityType = "unreliable",
		}),

		-- Server → All: someone reacted. `userId` is along for the ride so a
		-- future version can name the sender without another packet.
		Play = ByteNet.definePacket({
			value = ByteNet.struct({
				reactionId = ByteNet.string,
				userId = ByteNet.float64,
			}),
			reliabilityType = "unreliable",
		}),

		-- Client → Server: replace the whole bar. The whole list rather than
		-- one index because it's four short strings, and a full list can't get
		-- out of step with itself the way a stream of per-slot writes can.
		SetSlots = ByteNet.definePacket({
			value = ByteNet.struct({
				slots = ByteNet.array(ByteNet.string),
			}),
			reliabilityType = "reliable",
		}),
	}
end)
