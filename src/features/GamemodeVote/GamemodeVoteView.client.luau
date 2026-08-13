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

	React.useEffect(function()
		if active then
			frames.open(Constants.FRAME_ID)
		elseif frames.openFrameId == Constants.FRAME_ID then
			frames.close()
		end
	end, { active } :: { any })

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
	for _, voter in state.voters do
		local list = votersByOption[voter.optionId]
		if list == nil then
			list = {}
			votersByOption[voter.optionId] = list
		end
		table.insert(list, voter.userId)
	end

	return React.createElement(UIShell.Frame, {
		id = Constants.FRAME_ID,
	}, {
		Vote = React.createElement(GamemodeVoteUI, {
			options = options,
			votersByOption = votersByOption,
			secondsLeft = secondsLeft,
			winnerId = state.winnerId,
			onVote = GamemodeVoteController.castVote,
		}),
	})
end
