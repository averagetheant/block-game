-- Puts one registered hint into the general chat channel every
-- `INTERVAL_SECONDS`, forever, in an order that doesn't repeat itself.
--
-- Client-side on purpose. A system message is local to the player who sees it,
-- and a tip is advice for one player rather than an event the room shares — so
-- there's nothing for the server to say and no packet to send. Each client runs
-- its own clock from the moment it joined.
--
-- The rotation is a **shuffle bag**: every hint is shown once before any is
-- shown twice, and a fresh bag never opens with the hint the last one closed
-- on. Plain random repeats often enough at these intervals that a player reads
-- the same line twice in six minutes and stops reading the line at all.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Constants = require(ReplicatedStorage.Features.ChatHints.Constants)
local Registry = require(ReplicatedStorage.Features.ChatHints.Registry)

type Hint = Registry.Hint

local ChatHintsController = {}

local rng = Random.new()
local bag: { Hint } = {}
local lastId: string? = nil

-- The general channel, or nil on a place still running the legacy chat (where
-- TextChannels never appears). Yields up to CHANNEL_WAIT_SECONDS because chat
-- is built a moment after the client boots — Start runs in its own thread, so
-- waiting here holds nothing else up.
local function generalChannel(): TextChannel?
	local channels = TextChatService:WaitForChild("TextChannels", Constants.CHANNEL_WAIT_SECONDS)
	if channels == nil then
		return nil
	end
	local channel = channels:WaitForChild(Constants.CHANNEL, Constants.CHANNEL_WAIT_SECONDS)
	return if channel and channel:IsA("TextChannel") then channel else nil
end

-- Refill and shuffle. Hints are drawn off the *end* of the list, so the swap at
-- the bottom is what stops a bag from opening on the hint that just played.
local function refill()
	bag = Registry.list()

	for i = #bag, 2, -1 do
		local j = rng:NextInteger(1, i)
		bag[i], bag[j] = bag[j], bag[i]
	end

	if #bag > 1 and bag[#bag].id == lastId then
		bag[#bag], bag[1] = bag[1], bag[#bag]
	end
end

local function nextHint(): Hint?
	if #bag == 0 then
		refill()
	end
	-- Nothing registered: the mechanism is installed and no feature has anything
	-- to say. Silence is the right answer, and the loop keeps checking in case a
	-- registration lands later.
	if #bag == 0 then
		return nil
	end

	local hint = table.remove(bag) :: Hint
	lastId = hint.id
	return hint
end

function ChatHintsController.Start()
	if not Constants.Presentations.chat then
		return
	end

	local channel = generalChannel()
	if channel == nil then
		return
	end

	task.wait(Constants.FIRST_HINT_SECONDS)

	while true do
		local hint = nextHint()
		if hint ~= nil then
			channel:DisplaySystemMessage(
				`<font color="{Constants.PREFIX_COLOR}"><b>{Constants.PREFIX}</b></font>`
					.. ` <font color="{Constants.TEXT_COLOR}">{hint.text}</font>`
			)
		end
		task.wait(Constants.INTERVAL_SECONDS)
	end
end

return ChatHintsController
