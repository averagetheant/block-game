-- Store's funnels. Discovered by src/features/Analytics/init.luau at load time;
-- see docs/game/Analytics.md.
--
-- Four of the experience's ten funnel slots, and they're split by *how the
-- money moves* rather than by which window the player is looking at:
--
--   shop       soft currency out of a balance the player earned
--   product    Robux into a one-shot consumable
--   gamepass   Robux into a permanent unlock
--   inventory  no money at all — did the thing they bought get used
--
-- Collapsing the first three into one "purchase" funnel would be the obvious
-- saving, and it would hide the only comparison worth making: a shop funnel
-- that converts and a product funnel that doesn't means the prices are wrong,
-- while both failing at the same step means the card is.
--
-- The inventory funnel earns its slot because an unequipped purchase is the
-- clearest refund-risk signal there is, and it's the one thing a purchase
-- funnel can never show.
--
-- Onboarding steps 5–6 are allocated here; TowerGame owns 1–4.

return function(Analytics)
	-- ---------------------------------------------------------------- shop --
	-- Coins → a pack. A new session per visit to the shop window, so a player
	-- who opens the shop three times in a session is three rows rather than one
	-- long one.
	--
	-- "Pack Selected" and "Purchase Sent" look redundant and aren't: the gap
	-- between them is players who picked a pack and found they couldn't afford
	-- it, which is the single most actionable number in the whole economy.
	Analytics.registerFunnel({
		id = "shop",
		name = "Shop Purchase",
		scope = "One visit to the shop window.",
		steps = {
			"Shop Opened",
			"Tab Viewed",
			"Pack Selected",
			"Purchase Sent",
			"Pack Granted",
		},
	})

	-- ------------------------------------------------------------- product --
	-- Robux → a developer product (a coin bundle, a Nuke, a stage skip).
	--
	-- "Prompt Closed" sits between the prompt opening and the receipt on
	-- purpose. Roblox tells us the prompt closed whether or not it was paid
	-- for, so the drop from Closed to Granted is the cancel rate, separated
	-- from players who never opened the prompt at all.
	Analytics.registerFunnel({
		id = "product",
		name = "Robux Product",
		scope = "One purchase attempt on one developer product.",
		steps = {
			"Product Shown",
			"Prompt Requested",
			"Prompt Closed",
			"Receipt Granted",
		},
	})

	-- ------------------------------------------------------------ gamepass --
	-- Robux → a permanent unlock. Separate from `product` because the decision
	-- is a different one: a pass is bought once and considered, a consumable is
	-- bought on impulse mid-round, and averaging the two conversion rates
	-- describes neither.
	Analytics.registerFunnel({
		id = "gamepass",
		name = "Gamepass Purchase",
		scope = "One purchase attempt on one gamepass.",
		steps = {
			"Gamepass Shown",
			"Prompt Requested",
			"Prompt Closed",
			"Pass Owned",
		},
	})

	-- ----------------------------------------------------------- inventory --
	-- What happens after the purchase. A player who buys a skin and never
	-- equips it either couldn't find the inventory or didn't get what they
	-- expected, and both are fixable — but only if the drop-off is visible.
	Analytics.registerFunnel({
		id = "inventory",
		name = "Equip Flow",
		scope = "One visit to the inventory window.",
		steps = {
			"Inventory Opened",
			"Tab Viewed",
			"Pack Equipped",
		},
	})

	-- ---------------------------------------------------------- onboarding --
	-- Steps 5–6: the first purchase journey, after TowerGame's 1–4 establish
	-- that they've actually played.
	Analytics.registerOnboardingStep({ step = 5, name = "Shop Opened" })
	Analytics.registerOnboardingStep({ step = 6, name = "First Pack Owned" })
end
