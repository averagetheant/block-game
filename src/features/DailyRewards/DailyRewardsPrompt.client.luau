-- The nudge: on joining with a reward waiting, the window opens itself, the rest
-- of the screen goes dark behind it, and the only lit thing left is the card with
-- the pulsing Claim button on it.
--
-- Why bother, when the topbar button already wears a notice: a badge is an
-- invitation and this is a sentence. A run nobody is walked through on their
-- first day is a run only the players who needed it least ever finish, and the
-- whole point of a seven-day cycle is the seventh day.
--
-- Three rules it plays by:
--
--   * **Once per session, on join.** The auto-open fires the first time the
--     profile lands with something claimable and never again — a player who
--     closes it has answered the question, and a window that reopened itself
--     would be the game arguing.
--   * **The scrim belongs to the prompt, not to the window.** Opening the same
--     window yourself from the topbar darkens nothing: you chose to be there.
--   * **It stays for as long as there is something to claim.** Claiming while
--     another reward is still waiting leaves everything up, so the next card
--     lights up under the same scrim. With today's UTC-day rule that is at most
--     one — but "how many are waiting" is `Cycle`'s business, and this reads the
--     answer rather than assuming it.
--
-- Rendered by `DailyRewardsWindow` rather than as a root of its own, because its
-- two halves live on *either side* of the window in the stack: the scrim under
-- it, the notice over it. `PromptOverlay` draws them; this decides when.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Boil = require(ReplicatedStorage.Shared.Boil)
local UIShell = require(ReplicatedStorage.Features.UIShell)
local Constants = require(ReplicatedStorage.Features.DailyRewards.Constants)
local Cycle = require(ReplicatedStorage.Features.DailyRewards.Cycle)
local PromptOverlay = require(ReplicatedStorage.Features.DailyRewards.PromptOverlay)

-- Client-realm sibling, reached the same way the View reaches it.
local PlayerDataController = require(script.Parent.Parent.PlayerData.PlayerDataController)

return function()
	local frames = UIShell.useFrame()
	local saved = Boil.useReplica(PlayerDataController, Constants.PROFILE_KEY)

	-- Whether the prompt is what put the window up.
	local prompting, setPrompting = React.useState(false)
	local notice, setNotice = React.useState(false)
	-- One auto-open per session. A ref rather than state: nothing renders
	-- differently for it, and flipping it must not schedule a render of its own.
	local prompted = React.useRef(false)

	local loaded = saved ~= nil
	-- Nothing is decided until the profile has landed. `Cycle.resolve(nil, …)`
	-- reads as "never claimed, claim now" — the right answer for a new player and
	-- a lie for everybody else, for as long as the replica takes to arrive, and
	-- acting on it would open the window at a player who has nothing waiting.
	local canClaim = loaded and Cycle.resolve(saved, os.time()).canClaim

	local open = frames.open
	local close = frames.close
	local openFrameId = frames.openFrameId

	-- The live frame id, readable from inside a timer. Declared *first* so it is
	-- already up to date when the effects below run — React runs effects in the
	-- order they're declared, within one commit.
	local openNow = React.useRef(openFrameId)
	React.useEffect(function()
		openNow.current = openFrameId
	end, { openFrameId } :: { any })

	-- Join, with something waiting: open the window and darken the room.
	React.useEffect(function()
		if not loaded or prompted.current or not canClaim then
			return
		end
		prompted.current = true
		setPrompting(true)
		open(Constants.FRAME_ID)
	end, { loaded, canClaim, open } :: { any })

	-- The claim landed.
	--
	-- Detected as `canClaim` going true → false rather than by hearing back from
	-- the button, because the claim is the server's to judge: the replica diff is
	-- the only event that means the reward was actually handed over, and it is the
	-- same signal whether the player pressed Claim, ran `claimdaily`, or was
	-- granted it some way that doesn't exist yet.
	--
	-- `openFrameId` is deliberately not a dependency — the effect wants the value
	-- from the render where the claim landed, and re-running it when a frame opens
	-- or closes would fire the notice a second time on nothing.
	local wasClaimable = React.useRef(false)
	React.useEffect(function()
		local was = wasClaimable.current
		wasClaimable.current = canClaim
		-- Not a claim: either nothing has landed, or something is still waiting
		-- and the prompt should stay exactly as it is for the next card.
		if not loaded or canClaim or not was then
			return
		end
		-- Claimed from the console with the window shut. Nothing to celebrate over
		-- and nothing to close.
		if openNow.current ~= Constants.FRAME_ID then
			return
		end

		setNotice(true)

		local live = true
		task.delay(Constants.CLOSE_SECONDS, function()
			if not live then
				return
			end
			setPrompting(false)
			-- Only if it is still ours. `close` shuts whatever frame is open, and
			-- three seconds is long enough for the player to have opened another.
			if openNow.current == Constants.FRAME_ID then
				close()
			end
		end)
		task.delay(Constants.NOTICE_SECONDS, function()
			if live then
				setNotice(false)
			end
		end)

		return function()
			live = false
		end
	end, { loaded, canClaim, close } :: { any })

	-- The player closed the window themselves — its X, the topbar button, or by
	-- opening another frame. The scrim goes with it: a darkened screen with
	-- nothing over it is a game that looks broken.
	React.useEffect(function()
		if prompting and openFrameId ~= Constants.FRAME_ID then
			setPrompting(false)
		end
	end, { prompting, openFrameId } :: { any })

	-- Two booleans out. Everything this file knows is *when*; `PromptOverlay`
	-- owns what the two halves look like and which side of the window each lands
	-- on, and can be driven from sliders in UI Labs because of it.
	return React.createElement(PromptOverlay, {
		scrim = prompting,
		notice = notice,
	})
end
