-- Shared packet definitions. Both server (DailyRewardsService) and client
-- (DailyRewardsController) import this module; ByteNet handles serialization
-- and reliability over the underlying RemoteEvent.
--
-- Plain .luau file => splitter routes it to
-- ReplicatedStorage.Features.DailyRewards.Packets.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ByteNet = require(ReplicatedStorage.Packages.ByteNet)

return ByteNet.defineNamespace("DailyRewards", function()
	return {
		-- Client -> Server: claim the day the client believes is open.
		--
		-- The day is sent even though the server could work it out alone, and
		-- the server checks it matches: a client that's been sitting on the
		-- window across a UTC midnight would otherwise silently claim a
		-- different day than the one whose button was pressed. Mismatch is
		-- refused rather than corrected — the window re-renders off the replica
		-- and the player presses the day they can actually see.
		Claim = ByteNet.definePacket({
			value = ByteNet.struct({
				day = ByteNet.uint8,
			}),
			reliabilityType = "reliable",
		}),
	}
end)
