-- Shared packet definitions for GamemodeVote. Both realms require this module;
-- ByteNet handles the wire format and reliability.
--
-- Plain .luau file => splitter routes to ReplicatedStorage.Features.GamemodeVote.Packets.
--
-- There's no per-second tick: the server sends a deadline stamp and the clients
-- count down against it locally, the same deal as TowerGame's turn clock. State
-- goes out on change — a vote is a handful of clicks, not a stream.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ByteNet = require(ReplicatedStorage.Packages.ByteNet)

return ByteNet.defineNamespace("GamemodeVote", function()
	return {
		-- Client -> Server: "my vote is this one". A vote can be moved but never
		-- taken back, so there's no un-vote packet — sending the id you already
		-- hold re-stamps it and changes nothing else.
		-- Unknown ids and votes cast outside an open poll are dropped server-side.
		Cast = ByteNet.definePacket({
			value = ByteNet.struct({
				optionId = ByteNet.string,
			}),
			reliabilityType = "reliable",
		}),

		-- Server -> All: the whole poll. Small enough that a diff would cost more
		-- than it saves.
		State = ByteNet.definePacket({
			value = ByteNet.struct({
				-- Server-time stamp the poll closes at; 0 when no vote is running,
				-- which is also what tells the client to close the frame. Stays at
				-- its (now past) value through the result window so the winner has
				-- a moment on screen.
				endsAt = ByteNet.float64,
				-- "" while voting, then the winning gamemode id.
				winnerId = ByteNet.string,
				-- Gamemode ids in display order. Sent rather than read from the
				-- registry so the panels can't disagree about what's on the ballot.
				options = ByteNet.array(ByteNet.string),
				-- Who voted for what. The screen shows votes as the voters' own
				-- headshots, so it needs the ids, not a count.
				voters = ByteNet.array(ByteNet.struct({
					userId = ByteNet.float64,
					optionId = ByteNet.string,
					-- What that stamp counts for in the tally: 1, or more with
					-- the 2x Votes gamepass. Sent so the screen can say so — the
					-- count itself is the server's, and always was.
					weight = ByteNet.uint8,
					-- How many times this player has pressed a panel this poll,
					-- from 1. Nothing counts it — one player is one vote however
					-- many times they press — and it travels for one reason: it's
					-- what makes a *repeat* press of the panel a player already
					-- holds a different packet from the one before it. Without it
					-- that press is byte-identical to the last state, and every
					-- client concludes nothing happened rather than landing the
					-- stamp again. The server wraps it to this width itself, and a
					-- wrap re-stamps like any other change.
					stamps = ByteNet.uint8,
				})),
			}),
			reliabilityType = "reliable",
		}),
	}
end)
