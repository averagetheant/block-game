--!strict
-- layers — the one stacking order the whole UI agrees on.
--
-- Every feature's UI mounts as a sibling root under the single ScaleLayer (see
-- src/client/init.client.luau), so what draws in front of what is decided by the
-- ZIndex those roots carry — and by nothing else. Left unset they all sit on
-- Roblox's default of 1, and the tie is broken by the order React happened to
-- mount them in, which is a table iteration: stable enough to look correct in
-- Studio and free to flip the day another feature registers.
--
-- Two features that must stack in a particular order therefore need a number
-- they both know. Reading each other's constant is the coupling the framework
-- forbids — a feature has to be removable without its neighbour noticing — so
-- the scale lives out here, ordinal and naming nobody.
--
-- Deliberately *not* a theme token. A skin decides how a surface looks, never
-- whether it is in front; letting a skin swap the stacking order would make
-- "does my window cover the HUD" a question with a per-skin answer.
--
-- Gaps of 100 so a feature can slot its own pieces between two layers — a scrim
-- just under its window, a badge just over its panel — without adding an entry
-- here. Those in-between numbers are *child* ZIndex within one root, which is
-- the right place for them: only the root's number is anybody else's business.

local layers = {}

-- Behind the game's own HUD: a standing status surface that must never be in the
-- way of the thing it's describing. A badge saying "you're out of the rotation"
-- is the case this exists for — it has to be *findable*, not *in front*, and the
-- HUD it would otherwise cover is what the player is trying to read.
--
-- Negative rather than 0, because 0 and 1 are one step apart and this is meant to
-- be a floor rather than a near-tie. Anything on it is by definition coverable, so
-- don't put a control here that has to be reachable at all times — where another
-- root overlaps it, that root takes the clicks.
layers.underlay = -100

-- The game itself: HUDs, rails, world-anchored readouts, anything that is the
-- screen rather than something over it. This is Roblox's own default, so a root
-- that sets nothing is already on this layer — which is why nothing has to be
-- retrofitted for the scale to work.
layers.hud = 1

-- Windows and frames opened over the game. Above every HUD, so a window can't
-- end up behind a scoreboard that happened to mount first.
layers.window = 100

-- Feedback that must never be buried: a payout burst, a toast, anything that is
-- the game answering something the player just did. It draws over an open window
-- on purpose — a reward that lands while a window is up is exactly the case
-- where the animation is worth seeing, and it's the one this layer was added for
-- (see `TowerCashView` and the daily rewards prompt).
layers.flourish = 900

return layers
