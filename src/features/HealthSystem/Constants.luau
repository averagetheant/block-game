-- Shared config / tunables for HealthSystem.
-- Plain .luau file => shipped to ReplicatedStorage, readable from any realm.

return {
	MAX_HP = 100,
	REGEN_PER_SECOND = 1,
	REGEN_DELAY_AFTER_DAMAGE = 5,

	-- The demo HP badge in the top-left. Off for TowerGame: there's no combat,
	-- and with characters disabled there's nothing for it to describe.
	Presentations = {
		screen = false,
	},
}
