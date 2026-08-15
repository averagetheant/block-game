-- Shared packet definitions for Analytics. Both realms require this module.
--
-- Roblox's analytics methods are server-only, but half of what's worth
-- measuring is client-side: a window opening, a tab being looked at, a card
-- being clicked, a purchase prompt being dismissed. None of that reaches the
-- server on its own, so it's relayed.
--
-- The client sends *names*, never numbers: the funnel id and the step name,
-- which the server resolves against the same registry both realms loaded. A
-- client that made up a step reports nothing rather than logging a real step
-- under a wrong number — and a step number on the wire would be a number the
-- server had to trust.
--
-- Everything here is unreliable-by-nature but sent reliable anyway. A dropped
-- step doesn't corrupt anything, but it does read on the dashboard as a player
-- abandoning the funnel at that step, which is the exact signal these packets
-- exist to measure — so an occasional retransmit is cheaper than a false
-- drop-off.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ByteNet = require(ReplicatedStorage.Packages.ByteNet)

return ByteNet.defineNamespace("Analytics", function()
	return {
		-- Client → Server: one step of one funnel.
		--
		-- `sessionId` groups the steps of a single pass through the funnel (one
		-- visit to the shop, one purchase attempt). An empty string means "the
		-- session the server is already tracking for this player and funnel",
		-- which is the common case — the client rarely knows or cares which
		-- visit it's on, it just knows a card was clicked.
		Step = ByteNet.definePacket({
			value = ByteNet.struct({
				funnelId = ByteNet.string,
				stepName = ByteNet.string,
				sessionId = ByteNet.string,
			}),
			reliabilityType = "reliable",
		}),

		-- Client → Server: open a fresh funnel session and log its first step.
		-- Sent when the player starts a journey the server can't observe the
		-- beginning of — opening the shop is the whole example.
		Start = ByteNet.definePacket({
			value = ByteNet.struct({
				funnelId = ByteNet.string,
				stepName = ByteNet.string,
			}),
			reliabilityType = "reliable",
		}),

		-- Client → Server: a step of the experience-wide onboarding funnel.
		-- Carried by number because the onboarding funnel has no per-feature
		-- step list to resolve a name against — the numbers are the shared
		-- space. The server still bounds-checks it and looks up the registered
		-- name, so an unregistered number is dropped.
		Onboarding = ByteNet.definePacket({
			value = ByteNet.struct({
				step = ByteNet.uint8,
			}),
			reliabilityType = "reliable",
		}),
	}
end)
