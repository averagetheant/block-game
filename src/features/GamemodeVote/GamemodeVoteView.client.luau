-- Stateful container for the vote screen. Subscribes to the controller's store,
-- runs the clock locally off the server's deadline stamp, and opens / closes the
-- UIShell frame as the poll comes and goes.
--
-- Going through UIShell rather than mounting the screen directly is what gives
-- the vote the single-frame invariant (it takes over from whatever window the
-- player had up) and the blur + FOV focus effect, for free.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage.Packages.React)
local Boil = require(ReplicatedStorage.Shared.Boil)

local Constants = require(ReplicatedStorage.Features.GamemodeVote.Constants)
local GamemodeVoteUI = require(ReplicatedStorage.Features.GamemodeVote.GamemodeVoteUI)
local Registry = require(ReplicatedStorage.Features.GamemodeVote.Registry)
local UIShell = require(ReplicatedStorage.Features.UIShell)

-- Client-realm sibling (StarterPlayerScripts.Features.GamemodeVote.*).
local GamemodeVoteController = require(script.Parent.GamemodeVoteController)

return function()
	local state = Boil.useReplica(GamemodeVoteController)
	local frames = UIShell.useFrame()

	local active = state ~= nil and state.endsAt ~= 0

	-- The ballot claims the shell when a poll opens — taking over whatever window
	-- the player had up, because the poll is on a clock and it's the one thing
	-- everyone in the server should be looking at — and **reclaims** it whenever
	-- the shell goes empty while the poll is still running.
	--
	-- The reclaim closes a real hole. The shell holds one open frame, so opening
	-- another window (Daily Rewards off the topbar, anything off the sidebar)
	-- over a live ballot swapped the ballot out for it; closing that window left
	-- the shell empty. Nothing re-opened the vote, because this effect had no
	-- reason to run again — `active` hadn't changed — so the player spent the
	-- rest of the poll looking at a HUD with no ballot on it, and the round's
	-- rules were decided without them.
	--
	-- Only when the shell is *empty*, never while some other frame is open: a
	-- player is allowed to go and look at their rewards mid-poll, and a ballot
	-- that shoved its way back on top the moment anything else opened would be a
	-- fight rather than a takeover.
	local claimed = React.useRef(false)
	React.useEffect(function()
		if not active then
			claimed.current = false
			if frames.openFrameId == Constants.FRAME_ID then
				frames.close()
			end
			return
		end

		-- First run of this poll: take the shell whatever is in it.
		if not claimed.current then
			claimed.current = true
			frames.open(Constants.FRAME_ID)
			return
		end

		if frames.openFrameId == nil then
			frames.open(Constants.FRAME_ID)
		end
	end, { active, frames.openFrameId } :: { any })

	-- The server sends one deadline, not a tick, so the clock runs here. Only
	-- re-render when the displayed second changes — returning the previous value
	-- makes React bail out of the update entirely.
	local secondsLeft, setSecondsLeft = React.useState(0)
	React.useEffect(function()
		if not active then
			return nil
		end
		local connection = RunService.Heartbeat:Connect(function()
			local left = GamemodeVoteController.secondsLeft()
			setSecondsLeft(function(previous)
				if math.ceil(previous) == math.ceil(left) then
					return previous
				end
				return left
			end)
		end)
		return function()
			connection:Disconnect()
		end
	end, { active } :: { any })

	if state == nil or not active then
		return nil
	end

	-- The ballot arrives as ids; the names and icons come from the registry. An
	-- id with no local registration is dropped rather than drawn as a blank
	-- panel — it means this client is missing the feature that owns that mode.
	local options: { Registry.Gamemode } = {}
	for _, id in state.options do
		local mode = Registry.get(id)
		if mode == nil then
			continue
		end
		table.insert(options, mode)
	end

	local votersByOption: { [string]: { number } } = {}
	-- Kept beside the panels rather than inside them: a weight belongs to the
	-- voter, not to the option they picked, and the UI only needs it to tag the
	-- stamp.
	local voteWeights: { [number]: number } = {}
	-- Same shape, same reason, and the thing that makes a repeat press visible:
	-- the UI replays a stamp's slam whenever this number changes under it.
	local voteStamps: { [number]: number } = {}
	for _, voter in state.voters do
		local list = votersByOption[voter.optionId]
		if list == nil then
			list = {}
			votersByOption[voter.optionId] = list
		end
		table.insert(list, voter.userId)
		voteWeights[voter.userId] = voter.weight
		voteStamps[voter.userId] = voter.stamps
	end

	return React.createElement(UIShell.Frame, {
		id = Constants.FRAME_ID,
	}, {
		Vote = React.createElement(GamemodeVoteUI, {
			options = options,
			votersByOption = votersByOption,
			voteWeights = voteWeights,
			voteStamps = voteStamps,
			secondsLeft = secondsLeft,
			winnerId = state.winnerId,
			onVote = GamemodeVoteController.castVote,
		}),
	})
end
