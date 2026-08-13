-- Shared packet definitions for Store. Both realms require this module.
--
-- Only two things travel: "buy this pack" and "equip this pack". Neither
-- carries a price, a balance or an ownership flag — the client saying what it
-- wants and the server deciding what that costs is the whole point. Robux
-- purchases aren't here at all: those go through MarketplaceService's own
-- prompt and come back as a ProcessReceipt callback on the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ByteNet = require(ReplicatedStorage.Packages.ByteNet)

return ByteNet.defineNamespace("Store", function()
	return {
		-- Client → Server: buy the pack with its registered soft currency.
		Purchase = ByteNet.definePacket({
			value = ByteNet.struct({
				packId = ByteNet.string,
			}),
			reliabilityType = "reliable",
		}),

		-- Client → Server: equip an owned pack in its kind's slot. An empty
		-- packId unequips whatever is in that slot — "no skin" is a choice the
		-- player makes, so it needs to be sendable.
		Equip = ByteNet.definePacket({
			value = ByteNet.struct({
				kind = ByteNet.string,
				packId = ByteNet.string,
			}),
			reliabilityType = "reliable",
		}),
	}
end)
