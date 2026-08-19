-- Wire format for the PVP round.
--
-- Its own ByteNet namespace rather than more fields on `Packets.luau`: the
-- classic state packet describes one tower, one holder and a storm, and PVP has
-- none of those. Bolting six lanes onto it would mean every classic client
-- decoding a lane array it never reads, and every PVP client decoding a turn
-- order that doesn't exist.
--
-- What is *not* here is the placement pair. Aiming a piece is `Packets.Place` /
-- `Packets.Release` in both modes, unchanged: a placement is fully described by
-- an X and a quarter-turn count either way, and the server already knows which
-- piece belongs to which player. The one difference is that PVP's X is measured
-- from the player's own lane centre rather than from the world origin, which is
-- a matter of what the number *means* and not of how it travels — see
-- `TowerService.applyPlacement`.
--
-- One packet does the whole mode. The lane array carries every tower, including
-- the reader's own, so a client needs no second message to know where it stands
-- and the map shot needs no request of its own. It re-sends at least once a
-- second so a player who joins mid-match picks the round up without a handshake,
-- the same way the classic `State` packet does.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ByteNet = require(ReplicatedStorage.Packages.ByteNet)

return ByteNet.defineNamespace("TowerGamePvp", function()
	return {
		-- Server -> All: the whole match. Broadcast on change, plus a heartbeat.
		State = ByteNet.definePacket({
			value = ByteNet.struct({
				-- PvpConstants.PHASE. OFF means the classic game owns the world and
				-- everything else in here should be ignored.
				phase = ByteNet.uint8,
				-- When the current phase ends, as a `workspace:GetServerTimeNow()`
				-- stamp — clients count down locally rather than being fed a packet
				-- a second. One field for all three clocks (countdown, match,
				-- results) because only one of them is ever running.
				endsAt = ByteNet.float64,
				-- The match clock's full length, so the HUD can draw the time left
				-- as a fraction without reading a constant the server might have
				-- been told otherwise.
				matchSeconds = ByteNet.uint16,
				-- Current zone and which of the normal skies is up, exactly as the
				-- classic packet carries them — TowerZoneController reads either.
				zoneId = ByteNet.uint8,
				zoneSky = ByteNet.uint8,
				-- When that zone becomes true in the world, as a server-time stamp.
				-- The zone is announced `ZONE_ROLL_SECONDS` before it takes effect,
				-- and this is the far end of that window: the HUD spins its reel up
				-- to it and the client holds the sky, fog and lights back until it
				-- passes, while the server holds the gravity and the block dressing
				-- back to the same instant.
				--
				-- A stamp rather than a "rolling" flag, for the same reason `endsAt`
				-- is one: every client then lands with the world instead of with
				-- whenever its own packet happened to arrive. Already past for the
				-- zone a joiner walks in on, which reads as "no reveal owed" — the
				-- right answer for a zone that has been up for twenty seconds.
				zoneAt = ByteNet.float64,
				-- Every lane in the match, in slot order. A lane appears the moment
				-- its player is given one (including mid-match) and stays for the
				-- rest of the match — a player who stops playing keeps their tower
				-- and their place in the standings.
				lanes = ByteNet.array(ByteNet.struct({
					-- Whose lane it is. The client resolves the name itself; a name
					-- resolved from a user id is one nobody can have made up.
					userId = ByteNet.float64,
					-- 0 … PvpConstants.MAX_LANES - 1. The lane's world X is derived
					-- from this on both realms (`PvpLanes.xOf`), so the position
					-- itself never goes over the wire and can't disagree.
					slot = ByteNet.uint8,
					-- Studs above the lane platform's top surface. This is the
					-- score.
					height = ByteNet.float32,
					blockCount = ByteNet.uint16,
					-- Whether this player is aiming a piece right now, and the top
					-- of it in the same terms as `height`. The camera needs the
					-- second to guarantee the piece is on screen — see the note on
					-- `pieceTop` in Packets.luau, which this is the per-lane twin
					-- of.
					holding = ByteNet.bool,
					pieceTop = ByteNet.float32,
					-- When the piece being aimed drops itself, server time. 0 when
					-- nothing is held.
					pieceEndsAt = ByteNet.float64,
					-- What that piece is, as the same `shapeId` + `blockTypeId`
					-- pair the classic packet uses, so `BlockLabel.titleFor` names
					-- it identically in both modes.
					shapeId = ByteNet.uint8,
					blockTypeId = ByteNet.uint8,
				})),
			}),
			reliabilityType = "reliable",
		}),
	}
end)
