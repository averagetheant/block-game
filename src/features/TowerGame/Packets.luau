-- Shared packet definitions for TowerGame. Both realms require this module;
-- ByteNet handles the wire format and reliability.
--
-- Plain .luau file => splitter routes to ReplicatedStorage.Features.TowerGame.Packets.
--
-- Note what is *not* here: the piece's position. The active piece is a Model the
-- server owns in Workspace, so Roblox replicates its movement for us — steering
-- packets are three bytes of intent, not a transform stream.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ByteNet = require(ReplicatedStorage.Packages.ByteNet)

return ByteNet.defineNamespace("TowerGame", function()
	return {
		-- Client -> Server: steer the held piece one cell left (-1) or right (1).
		Steer = ByteNet.definePacket({
			value = ByteNet.struct({
				dir = ByteNet.int8,
			}),
			reliabilityType = "reliable",
		}),

		-- Client -> Server: rotate the held piece a quarter turn.
		Spin = ByteNet.definePacket({
			value = ByteNet.struct({
				clockwise = ByteNet.bool,
			}),
			reliabilityType = "reliable",
		}),

		-- Client -> Server: release the held piece to physics.
		Release = ByteNet.definePacket({
			value = ByteNet.struct({
				-- Reserved for a future "slam" variant; the server ignores it today
				-- but the field keeps the schema stable when it lands.
				instant = ByteNet.bool,
			}),
			reliabilityType = "reliable",
		}),

		-- Server -> All: the whole game state, broadcast on change (not on a
		-- tick). `turnEndsAt` is a `workspace:GetServerTimeNow()` stamp, so
		-- clients count down locally instead of us shipping a per-second packet.
		State = ByteNet.definePacket({
			value = ByteNet.struct({
				phase = ByteNet.uint8,
				-- 0 when nobody holds a piece.
				holderUserId = ByteNet.float64,
				turnEndsAt = ByteNet.float64,
				-- Studs above the base platform's top surface.
				height = ByteNet.float32,
				maxHeight = ByteNet.float32,
				blockCount = ByteNet.uint16,
				shapeId = ByteNet.uint8,
				nextShapeId = ByteNet.uint8,
				queueCount = ByteNet.uint8,
			}),
			reliabilityType = "reliable",
		}),
	}
end)
