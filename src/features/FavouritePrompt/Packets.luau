-- Shared packet definitions for FavouritePrompt. Both realms require this module.
--
-- One packet, one direction, no payload. The trigger and the prompt are both
-- client-side (AvatarEditorService only exists there, and only the client knows
-- the ballot reached its screen), so the client is what reports the ask —
-- the server's job is to write it down.
--
-- Nothing rides on the wire because there's nothing the server would believe: it
-- doesn't take the client's word for *whether* the flag should flip, only for
-- "I showed it", and the flip is one-way and idempotent (see the service).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ByteNet = require(ReplicatedStorage.Packages.ByteNet)

return ByteNet.defineNamespace("FavouritePrompt", function()
	return {
		-- Client → Server: "the prompt is on my screen; don't ask me again."
		Shown = ByteNet.definePacket({
			value = ByteNet.nothing,
			reliabilityType = "reliable",
		}),
	}
end)
