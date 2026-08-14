-- Shared packet definitions for TowerGame. Both realms require this module;
-- ByteNet handles the wire format and reliability.
--
-- Plain .luau file => splitter routes to ReplicatedStorage.Features.TowerGame.Packets.
--
-- The split of responsibility: the holder's client owns how aiming *feels* and
-- reports where the piece is; the server owns whether that's allowed (it clamps
-- every value) and everything that happens after the drop. So there's no
-- "move left" packet — a placement is fully described by an X on the play plane
-- and a number of quarter turns, and that's what gets sent.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ByteNet = require(ReplicatedStorage.Packages.ByteNet)

return ByteNet.defineNamespace("TowerGame", function()
	return {
		-- Client -> Server: where the holder currently has the piece. Streamed
		-- while it's moving, throttled to Constants.AIM_INTERVAL. Only one player
		-- aims at a time, so this is a few packets a second for the whole server.
		-- Dropping one costs nothing: the next carries the full placement, and
		-- Release carries the final word.
		Place = ByteNet.definePacket({
			value = ByteNet.struct({
				x = ByteNet.float32,
				-- Quarter turns clockwise, 0-3.
				turns = ByteNet.uint8,
			}),
			reliabilityType = "reliable",
		}),

		-- Client -> Server: drop it, here. Carries the placement rather than
		-- relying on the last Place having landed, so the piece falls exactly
		-- where the holder saw it.
		Release = ByteNet.definePacket({
			value = ByteNet.struct({
				x = ByteNet.float32,
				turns = ByteNet.uint8,
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
				-- Top of the piece the holder is currently aiming, in the same terms
				-- as `height`; 0 when nobody holds one. A piece always spawns clear
				-- of the tower, so it can sit well above `height` — this is what lets
				-- the camera guarantee it's on screen without the client having to
				-- work out how tall the piece is.
				pieceTop = ByteNet.float32,
				blockCount = ByteNet.uint16,
				shapeId = ByteNet.uint8,
				-- BlockTypes id of the current piece, 0 for an ordinary block.
				-- The HUD names the piece from the pair: a type that brings its
				-- own model (the Noob) sends shapeId 0 and is named from this.
				blockTypeId = ByteNet.uint8,
				nextShapeId = ByteNet.uint8,
				-- Turn order as user ids, current holder first. The HUD's headshot
				-- strip rotates this so the holder lands dead center; the entry at
				-- the end is whoever played immediately before (the cycle wraps).
				order = ByteNet.array(ByteNet.float64),
				-- The player who takes the *next* piece as well as this one,
				-- because they own Double Turn; 0 when nobody does. Sent instead
				-- of listing them in `order` twice: the strip keys its chips by
				-- user id, so a second entry would be the same chip, not a
				-- second slot. The HUD badges them "2x" and the order stays
				-- honest about who is actually up next.
				repeatUserId = ByteNet.float64,
				-- Storm stage: the height to beat, when the clock runs out (server
				-- time, same deal as turnEndsAt), and how many checkpoint
				-- platforms have been earned so far.
				targetHeight = ByteNet.float32,
				-- Height the current stage started from. The progress line runs
				-- from here to targetHeight, so it measures *this leg* of the
				-- climb rather than the whole tower.
				zoneBaseHeight = ByteNet.float32,
				stormEndsAt = ByteNet.float64,
				checkpoints = ByteNet.uint8,
				-- Current zone (see Zones.luau) plus which of the normal skies is
				-- up, so every client paints the same world.
				zoneId = ByteNet.uint8,
				zoneSky = ByteNet.uint8,
				-- The stage's two clock lengths. Constants until a gamemode vote
				-- changes them (see Gamemodes.luau), and the HUD draws both as
				-- fractions — the turn ring against one, the storm bar against the
				-- other — so a client reading them off Constants would draw the
				-- wrong shape for a voted stage.
				turnSeconds = ByteNet.uint8,
				stormSeconds = ByteNet.uint16,
			}),
			reliabilityType = "reliable",
		}),
	}
end)
