-- Shows the Double Turn row only to players who own the pass.
--
-- The setting itself is registered in this feature's shared Settings.luau, and
-- has to be: both realms need to agree the id exists or SettingsService rejects
-- every write to it. What can't live there is the *gate* — ownership is a
-- MarketplaceService answer, and a shared file asking for it would drag that
-- call onto the server, which has its own (cached, authoritative) answer already.
-- So the row is registered shared and gated here, in client-only code, which is
-- the only realm where "shown" means anything.
--
-- Registered as a presentation rather than from a controller because that's what
-- this is: a decision about what the player sees, with no state of its own. It
-- carries no `Presentations` flag, unlike the surfaces around it — the flags turn
-- a surface *off*, and turning this one off wouldn't hide anything, it would show
-- the row to everybody.
--
-- Ownership arrives a moment after join, so the answer is re-asked when it
-- changes rather than read once — an owner who opened Settings during the first
-- second would otherwise never see the row appear.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)
local Settings = require(ReplicatedStorage.Features.Settings)

-- Client-realm sibling from another feature (StarterPlayerScripts.Features).
local StoreController = require(script.Parent.Parent.Store.StoreController)

Settings.setVisibility(Constants.SETTING_DOUBLE_TURN, function()
	return StoreController.ownsGamepass(Constants.GAMEPASSES.DOUBLE_TURN)
end)

StoreController.GamepassesChanged:Connect(function()
	Settings.invalidate()
end)

return {}
