-- Feedback — a topbar button, on the right beside Roblox's own controls, that
-- opens Roblox's in-experience feedback panel.
--
-- The whole feature is one icon and one call: `SocialService`'s
-- `PromptFeedbackSubmissionAsync` hands the screen to Roblox, the player writes
-- what they think, and it arrives in the Creator Dashboard. Nothing here stores,
-- sends or renders any of it — there is no packet, no profile slice and no
-- window, which is the reason to use Roblox's panel over a home-made one.
--
-- See docs/game/Feedback.md.

local Feedback = {}

Feedback.Constants = require(script.Constants)

return Feedback
