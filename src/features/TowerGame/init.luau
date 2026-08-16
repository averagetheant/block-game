-- TowerGame — a Tricky Towers-style co-op stacking game. Players take turns
-- dropping tetromino pieces onto one shared tower; the camera rides the tower's
-- highest altitude and the HUD tracks current and best height.
--
-- See docs/game/TowerGame.md for the turn loop, the arena, and the tunables.

local TowerGame = {}

TowerGame.Constants = require(script.Constants)
TowerGame.Shapes = require(script.Shapes)
TowerGame.UI = require(script.TowerHUD)
TowerGame.AfkNotice = require(script.AfkNotice)
TowerGame.SpectatorNotice = require(script.SpectatorNotice)

return TowerGame
