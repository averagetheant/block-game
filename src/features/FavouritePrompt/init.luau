-- FavouritePrompt — asks a player to favourite the experience, once, at the
-- first gamemode vote they ever see.
--
-- The whole feature is a *moment* and a flag. Roblox draws the prompt
-- (`AvatarEditorService:PromptSetFavorite`), the profile remembers the ask, and
-- GamemodeVote supplies the beat to make it on: the round is over, nothing is
-- being built, and the game is already asking a question.
--
-- It names GamemodeVote and PlayerData and nothing names it. Remove it and the
-- vote is unchanged.
--
-- See docs/game/FavouritePrompt.md.

local FavouritePrompt = {}

FavouritePrompt.Constants = require(script.Constants)

return FavouritePrompt
