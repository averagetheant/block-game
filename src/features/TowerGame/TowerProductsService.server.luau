-- What TowerGame's three Robux action products actually do.
--
-- The receipt itself is Store's business (one ProcessReceipt per game); this
-- only says what "Nuke" means — including the fact that it means something
-- different while a PVP match owns the board. Keeping the handler here rather
-- than in Store.luau is deliberate: Store.luau loads on both realms and these call
-- server code, and it keeps Store from ever learning that a nuke exists.
--
-- Every handler returns false when the game is mid-checkpoint. That's not a
-- failure — Store leaves the receipt undelivered and Roblox re-delivers it, so
-- the player gets the thing they paid for a moment later instead of losing it.
--
-- All three announce themselves in chat. These are the purchases the whole room
-- feels — a tower gone, a stage skipped, a minute back on everyone's clock — so
-- the room gets told who did it, and the announcement rides on the same `false`
-- as the effect: a deferred receipt says nothing until the retry lands.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)
local Packets = require(ReplicatedStorage.Features.TowerGame.Packets)
local PvpService = require(ServerScriptService.Features.TowerGame.PvpService)
local StoreService = require(ServerScriptService.Features.Store.StoreService)
local TowerService = require(ServerScriptService.Features.TowerGame.TowerService)

local TowerProductsService = {}

-- After Store (10), which owns the handler registry.
TowerProductsService.Priority = 25

-- Wraps a handler so a purchase that landed is announced to the room and one
-- that was deferred isn't. Every product goes through here rather than each
-- handler remembering to announce itself — the pairing is the rule, not a
-- courtesy three call sites happen to observe.
local function announced(productId: number, apply: (player: Player) -> boolean): (player: Player) -> boolean
	return function(player: Player): boolean
		if not apply(player) then
			return false
		end
		Packets.Announce.sendToAll({ productId = productId, userId = player.UserId })
		return true
	end
end

function TowerProductsService.Start()
	if not Constants.Presentations.actions then
		return
	end

	-- Nuke means two different things depending on which mode owns the board, and
	-- it's one product either way: same id, same price, same button. In the
	-- classic run there is one tower and it's everyone's, so it goes. In a match
	-- there are six and one of them belongs to the buyer, so the other five go —
	-- see `PvpService.nukeOthers`. The rail says which one you're buying: the
	-- entry reads "Nuke Others" during a match (see TowerProductsPresentation).
	--
	-- Tried in that order rather than branched on "is a match running", because
	-- each call already knows whether it applies and neither can fire in the
	-- other's mode: `nukeOthers` is false outside `PLAYING`, and a match runs
	-- *inside* the classic round break, which is exactly when `TowerService.nuke`
	-- refuses. Asking a flag instead would put a third opinion between them, and
	-- a wrong one would silently defer the purchase forever.
	StoreService.registerProductHandler(
		Constants.PRODUCTS.NUKE,
		announced(Constants.PRODUCTS.NUKE, function(player)
			if PvpService.nukeOthers(player) then
				return true
			end
			return TowerService.nuke()
		end)
	)

	-- No PVP branch, and none needed: a match has no checkpoints to skip, and it
	-- runs inside the round break that `clearStage` already refuses to fire
	-- during. The sidebar entry is hidden for the duration too, so the only way in
	-- here mid-match is a re-delivered receipt — which defers again and is
	-- honoured once the round comes back.
	StoreService.registerProductHandler(
		Constants.PRODUCTS.NEXT_CHECKPOINT,
		announced(Constants.PRODUCTS.NEXT_CHECKPOINT, function()
			return TowerService.clearStage()
		end)
	)

	StoreService.registerProductHandler(
		Constants.PRODUCTS.EXTEND_STORM,
		announced(Constants.PRODUCTS.EXTEND_STORM, function()
			return TowerService.extendStorm(Constants.EXTEND_STORM_SECONDS)
		end)
	)
end

return TowerProductsService
