--!strict
-- Tunables for the vote. The clock is deliberately short: this runs between
-- stages while everything else is parked, so every second here is a second the
-- players aren't building.

return {
	-- UIShell frame id. The vote opens itself on this id, which is also what
	-- gives it the single-frame invariant (opening the vote closes whatever
	-- window the player had up) and the blur/FOV focus effect for free.
	FRAME_ID = "GamemodeVote",

	-- How long the poll is open.
	VOTE_SECONDS = 15,

	-- How many panels a ballot holds. Every `pinned` mode is always on it; the
	-- rest of the slots are filled at random from what's left, re-rolled per
	-- vote. Registering a tenth gamemode should make the ballot more varied, not
	-- wider — three panels is what fits a phone in landscape, and a wall of
	-- options is a worse choice than a short one.
	BALLOT_SIZE = 3,

	-- How long the winner stays on screen after the clock ends, before the frame
	-- closes and play resumes.
	RESULT_SECONDS = 3,

	-- The 2x Votes gamepass, configured on the Roblox place. Its owner's stamp
	-- counts for DOUBLE_VOTE_WEIGHT in the tally instead of 1 — one stamp, worth
	-- more. Ownership is read on the *server* (StoreService.ownsGamepass); the
	-- weight goes out with the poll only so the screen can say so.
	--
	-- The card for it is registered in this feature's Store.luau.
	GAMEPASS_DOUBLE_VOTE = 1948166343,
	DOUBLE_VOTE_WEIGHT = 2,

	-- The thud a landing stamp makes. A Studio-authored Sound of this name under
	-- `ReplicatedStorage.Assets.Sounds`, played through `Boil.audio.playCue` — a
	-- missing one costs the cue and nothing else.
	STAMP_SOUND = "Stamp",
	-- Quieter than a full-volume cue: during a poll this can fire once per voter
	-- in quick succession, and at full weight a busy server sounds like hail.
	STAMP_VOLUME = 0.7,

	-- Which presentations are active. The screen is the vote; the command only
	-- *starts* one, so a dev doesn't have to play out a whole storm stage to see
	-- it. A world part can't express "pick one of three, now", so there's none.
	Presentations = {
		screen = true,
		command = true,
	},
}
