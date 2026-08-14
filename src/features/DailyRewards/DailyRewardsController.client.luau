local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Features.DailyRewards.Constants)
local Packets = require(ReplicatedStorage.Features.DailyRewards.Packets)

local DailyRewardsController = {}

-- Called by the window's Claim button. Fires a packet and stops — the server
-- judges the claim, grants, and writes the streak, and the replica diff is what
-- moves the card to "Claimed". Nothing is applied locally: a client that drew
-- its own optimistic tick would show a reward the server refused.
function DailyRewardsController.claim(day: number)
	if typeof(day) ~= "number" or day < 1 or day > Constants.MAX_DAY then
		return
	end
	Packets.Claim.send({ day = math.floor(day) })
end

function DailyRewardsController.Start()
	-- Nothing to wire; claim is called from the UI on demand.
end

return DailyRewardsController
