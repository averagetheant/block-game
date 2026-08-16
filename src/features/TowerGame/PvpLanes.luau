--!strict
-- Where a PVP lane stands.
--
-- One tiny module because both realms need the same answer and neither may
-- derive it independently: the server builds the platform and spawns the pieces
-- at these coordinates, the client points its camera at them and frames the map
-- shot around them. Only the *slot* travels on the wire (see PvpPackets), so
-- this file is the single place a slot becomes a position — a second copy of the
-- arithmetic is a client whose camera looks a hundred studs to the left of the
-- tower it's meant to be watching.
--
-- Slots are fixed seats, not a packed list. Slot 2 is in the same place whether
-- three players are in the match or six, so a lane never slides sideways because
-- somebody else joined or left, and the map shot's framing is the same shot for
-- the whole round.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PvpConstants = require(ReplicatedStorage.Features.TowerGame.PvpConstants)

local PvpLanes = {}

-- World X of a lane's centre line.
--
-- The seats are laid out symmetrically about the arena's origin: with six of
-- them the outer pair sit at ±2.5 spacings, so the board is centred on x = 0
-- whichever seats are taken. That's what lets the map shot aim straight down the
-- middle without working out who is playing, and it keeps the classic arena's
-- origin meaningful in both modes.
function PvpLanes.xOf(slot: number): number
	return (slot - (PvpConstants.MAX_LANES - 1) / 2) * PvpConstants.LANE_SPACING
end

-- Half the width the whole board occupies, from the origin to the outer edge of
-- an outer lane's platform. What the map shot has to fit across.
function PvpLanes.halfWidth(): number
	return PvpLanes.xOf(PvpConstants.MAX_LANES - 1) + PvpConstants.LANE_PLATFORM_SIZE.X / 2
end

return PvpLanes
