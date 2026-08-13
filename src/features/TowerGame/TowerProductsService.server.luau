-- What TowerGame's two Robux action products actually do.
--
-- The receipt itself is Store's business (one ProcessReceipt per game); this
-- only says what "Nuke" means. Keeping the handler here rather than in
-- Store.luau is deliberate: Store.luau loads on both realms and these call
-- server code, and it keeps Store from ever learning that a nuke exists.
--
-- Both handlers return false when the game is mid-checkpoint. That's not a
-- failure — Store leaves the receipt undelivered and Roblox re-delivers it, so
-- the player gets the thing they paid for a moment later instead of losing it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)
local StoreService = require(ServerScriptService.Features.Store.StoreService)
local TowerService = require(ServerScriptService.Features.TowerGame.TowerService)

local TowerProductsService = {}

-- After Store (10), which owns the handler registry.
TowerProductsService.Priority = 25

function TowerProductsService.Start()
	if not Constants.Presentations.actions then
		return
	end

	StoreService.registerProductHandler(Constants.PRODUCTS.NUKE, function()
		return TowerService.nuke()
	end)

	StoreService.registerProductHandler(Constants.PRODUCTS.NEXT_CHECKPOINT, function()
		return TowerService.clearStage()
	end)
end

return TowerProductsService
