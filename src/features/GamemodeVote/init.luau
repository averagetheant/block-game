-- GamemodeVote — the between-stages poll. Three-ish panels, one vote each,
-- a clock, and a winner handed back to whoever asked for the vote.
--
-- The feature owns no gamemodes. A feature adds one by dropping a sibling
-- `Gamemode.luau` that returns `function(GamemodeVote) ... end` and calls
-- `GamemodeVote.register{ … }` — the same convention PlayerData and Settings
-- use, though the discovery pass itself lives in Registry.luau (see the note
-- there). So this folder names no other feature, and TowerGame's modes live in
-- TowerGame.
--
-- See docs/game/GamemodeVote.md for the flow and the wire format.

local GamemodeVote = {}

GamemodeVote.Constants = require(script.Constants)

local Registry = require(script.Registry)
GamemodeVote.register = Registry.register
GamemodeVote.get = Registry.get
GamemodeVote.list = Registry.list

GamemodeVote.UI = require(script.GamemodeVoteUI)

GamemodeVote.FRAME_ID = GamemodeVote.Constants.FRAME_ID

return GamemodeVote
