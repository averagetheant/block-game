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
-- somebody else joined or left. What *does* answer to how many seats are taken is
-- the map shot, which is framed from `spanOf` — the towers hold still and the
-- camera moves, rather than the other way round.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)
local PvpConstants = require(ReplicatedStorage.Features.TowerGame.PvpConstants)

local PvpLanes = {}

-- Half the width one lane needs in frame.
--
-- Wider than the platform, because a tower is wider than the platform: a piece
-- steers to ±STEER_LIMIT_X and overhangs half a block past that, which is what
-- CAMERA_MIN_HALF_WIDTH already measures for the classic shot. Framing a lane to
-- its slab would crop the overhang off both sides of the outer towers.
local function laneHalfWidth(): number
	return math.max(PvpConstants.LANE_PLATFORM_SIZE.X / 2, Constants.CAMERA_MIN_HALF_WIDTH)
end

-- World X of a lane's centre line.
--
-- The seats are laid out symmetrically about the arena's origin: with six of
-- them the outer pair sit at ±2.5 spacings, so a full board is centred on x = 0
-- and the classic arena's origin stays meaningful in both modes. Which seats are
-- *taken* is a separate question, and the map shot's — see `spanOf`.
function PvpLanes.xOf(slot: number): number
	return (slot - (PvpConstants.MAX_LANES - 1) / 2) * PvpConstants.LANE_SPACING
end

-- Half the width the whole board occupies, from the origin to the outer edge of
-- an outer lane. What a map shot of every seat would have to fit across.
function PvpLanes.halfWidth(): number
	return PvpLanes.xOf(PvpConstants.MAX_LANES - 1) + laneHalfWidth()
end

-- Where the lanes that are actually *taken* sit: the centre line between them and
-- half the width they span, which is what the map shot is framed from.
--
-- The seats stay fixed — slot 2 is in the same place whether three players are in
-- the match or six, which is the whole point of `xOf` — but a shot framed for six
-- of them when two are playing is two towers in the middle of a screen of empty
-- sky, and with the low seats filled first it isn't even *centred* empty sky. So
-- the seats don't move and the camera does.
--
-- Takes the outermost taken slots rather than a count, so a lane retired out of
-- the middle (its player left) doesn't collapse the framing onto the survivors
-- and swing the two towers either side of the gap outward. It also keeps this
-- allocation-free for the caller, which asks once per rendered frame.
--
-- An empty range (`lowest > highest`, which is what a caller that found no lanes
-- passes) falls back to the whole board — a match nobody is in has nothing else
-- to look at.
function PvpLanes.spanBetween(lowest: number, highest: number): (number, number)
	if lowest > highest then
		return 0, PvpLanes.halfWidth()
	end

	local left, right = PvpLanes.xOf(lowest), PvpLanes.xOf(highest)
	return (left + right) / 2, (right - left) / 2 + laneHalfWidth()
end

return PvpLanes
