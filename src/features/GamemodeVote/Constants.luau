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

	-- Which presentations are active. The screen is the vote; the command only
	-- *starts* one, so a dev doesn't have to play out a whole storm stage to see
	-- it. A world part can't express "pick one of three, now", so there's none.
	Presentations = {
		screen = true,
		command = true,
	},
}
