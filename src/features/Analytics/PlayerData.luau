-- Analytics' slice of the PlayerData profile template. Discovered by
-- src/features/PlayerData/init.luau at load time; see docs/game/PlayerData.md.
--
-- One number, and it exists because Roblox's onboarding funnel is a once-per-
-- *user* funnel rather than a once-per-session one. Nothing on Roblox's side
-- dedupes it: firing "First Block Placed" on every join would report a player
-- who has been here for a month as a brand new one converting again, and the
-- new-player retention curve — the entire point of that funnel — would read as
-- healthy no matter what the game did.
--
-- Storing the high-water mark rather than a set of claimed steps keeps this to
-- one integer, and matches how the funnel is actually shaped: the steps are a
-- ladder, and reaching step 4 means you passed 1 through 3.

return function(PlayerData)
	PlayerData.registerTemplate("Analytics", {
		-- Highest onboarding funnel step this user has ever reached. 0 = they
		-- have not been counted into the funnel at all yet.
		Onboarding = 0,
	})
end
