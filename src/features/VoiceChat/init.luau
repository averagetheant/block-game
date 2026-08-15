-- VoiceChat — server-wide voice, and a corner readout of who's using it.
--
-- See docs/game/VoiceChat.md for the audio graph, the two Studio settings it
-- depends on, and how speaking is detected.

local VoiceChat = {}

VoiceChat.Constants = require(script.Constants)
VoiceChat.SpeakerList = require(script.SpeakerList)

return VoiceChat
