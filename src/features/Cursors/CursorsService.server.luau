-- Server core for Cursors: the only place a reported position is trusted, and
-- the one thing that decides what the room sees.
--
-- It does almost nothing, and that's correct — a cursor is ambient. What it does
-- own is the two things a client must not: clamping a position into the play
-- area (a cosmetic must not become a way to draw on the sky), and forgetting a
-- cursor that has stopped reporting, so a player who alt-tabbed or turned the
-- feature off doesn't leave a pointer hanging in the air.
--
-- Positions are never stored on a profile. A cursor is true for a twelfth of a
-- second; persisting one would be persisting noise.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Features.Cursors.Constants)
local Packets = require(ReplicatedStorage.Features.Cursors.Packets)

local CursorsService = {}

-- Leaf service: nothing waits on it.
CursorsService.Priority = 40

type Cursor = {
	x: number,
	y: number,
	-- os.clock of the last report, for the staleness sweep.
	at: number,
}

local cursors: { [Player]: Cursor } = {}

local function onMove(payload: { x: number, y: number }, player: Player)
	local x, y = payload.x, payload.y
	-- NaN fails every comparison, so it would sail through a clamp and land in
	-- the packet as a position no client can render.
	if x ~= x or y ~= y then
		return
	end

	cursors[player] = {
		x = math.clamp(x, -Constants.LIMIT_X, Constants.LIMIT_X),
		y = math.clamp(y, Constants.MIN_Y, Constants.MAX_Y),
		at = os.clock(),
	}
end

-- Everything still reporting, as the wire sees it. Drops stale entries as it
-- goes, so the sweep and the broadcast are the same pass.
local function collect(): { { userId: number, x: number, y: number } }
	local now = os.clock()
	local live = {}
	for player, cursor in cursors do
		if player.Parent ~= Players then
			cursors[player] = nil
			continue
		end
		if now - cursor.at > Constants.STALE_SECONDS then
			cursors[player] = nil
			continue
		end
		table.insert(live, { userId = player.UserId, x = cursor.x, y = cursor.y })
	end
	return live
end

function CursorsService.Start()
	Packets.Move.listen(onMove)

	Players.PlayerRemoving:Connect(function(player)
		cursors[player] = nil
	end)

	-- One broadcast for the room on the same cadence a client reports at. Every
	-- client needs every cursor (each one filters out its own), so this is a
	-- genuine broadcast rather than a fan-out of per-player packets.
	task.spawn(function()
		-- The empty list has to go out *once* when the last cursor disappears, or
		-- every client keeps drawing whatever the final non-empty packet said.
		-- After that one, silence: an idle server — or one where everybody has
		-- cursors switched off — should cost nothing.
		local sentEmpty = true
		while true do
			task.wait(Constants.SEND_INTERVAL)
			local live = collect()
			if #live == 0 and sentEmpty then
				continue
			end
			sentEmpty = #live == 0
			Packets.State.sendToAll({ cursors = live })
		end
	end)
end

return CursorsService
