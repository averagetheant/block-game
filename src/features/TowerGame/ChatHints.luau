-- Auto-discovery file picked up by the ChatHints feature's `init.luau` loop.
-- Every tip about *this* game lives here — the storm, the turn clock, the
-- pieces, the modes — so ChatHints itself knows nothing about towers.
--
-- Receives the ChatHints table as a parameter to avoid a circular require: this
-- file never imports Features.ChatHints directly. Loaded on both realms, so it
-- reads tunables and nothing else.
--
-- The numbers are interpolated from Constants rather than typed out, because a
-- tip that quotes a clock the game no longer runs on is worse than no tip.

return function(ChatHints)
	local Constants = require(script.Parent.Constants)

	ChatHints.registerHints({
		{
			id = "tower.supports",
			order = 1,
			text = "The stronger the supports of the tower are, the more likely it'll stand!",
		},
		{
			id = "tower.wide-base",
			order = 2,
			text = "A wide, flat course near the bottom carries everything above it — spend a turn on the foundation and the next ten get easier.",
		},
		{
			id = "tower.storm-clock",
			order = 3,
			text = `The storm doesn't wait for anyone's turn. Reach the target height before the clock runs out or it takes the whole tower — the first checkpoint is {Constants.STORM_FIRST_TARGET} studs up.`,
		},
		{
			id = "tower.checkpoint-floor",
			order = 4,
			text = "Clearing a stage leaves a permanent platform behind and clears out the scaffolding below it — anything still falling above the line survives.",
		},
		{
			id = "tower.overshoot",
			order = 5,
			text = "Overshooting a target doesn't make the next stage free: the next one is measured from the height you actually reached.",
		},
		{
			id = "tower.idle-turn",
			order = 6,
			text = `An untouched turn is only {Constants.IDLE_TURN_SECONDS} seconds long. Steer or spin your piece and you get the full {Constants.TURN_SECONDS}.`,
		},
		{
			id = "tower.drop-counts",
			order = 7,
			text = "Dropping a piece straight down the middle still counts as taking your turn — pressing drop is playing, however still the piece was.",
		},
		{
			id = "tower.afk",
			order = 8,
			text = `Miss {Constants.IDLE_TURNS_BEFORE_AFK} turns in a row and the queue skips you until you say you're back. Hit "I'm here!" on the card to rejoin.`,
		},
		{
			id = "tower.special-pieces",
			order = 9,
			text = "Some pieces aren't ordinary blocks — bombs, burning blocks and Noobs turn up in the rotation. Every piece wears a name plate saying which.",
		},
		{
			id = "tower.noob-height",
			order = 10,
			text = "A Noob block walks around, so it never counts toward the tower's height. Build over it, not on it.",
		},
		{
			id = "tower.settle",
			order = 11,
			text = "Height only counts blocks that have come to rest. A tower knocked loose stops paying out until it settles again.",
		},
		{
			id = "tower.vote",
			order = 12,
			text = "Between rounds the room votes on how the next one plays. Classic is always on the ballot if you'd rather skip the twist.",
		},
		{
			id = "tower.pvp",
			order = 13,
			text = "Vote PVP for the other game: six lanes, no turns, and the tallest tower when the clock stops wins.",
		},
	})
end
