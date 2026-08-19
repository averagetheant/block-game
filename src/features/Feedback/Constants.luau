--!strict
-- Tunables for Feedback — the topbar button that opens Roblox's own feedback
-- panel.
--
-- Plain .luau => ReplicatedStorage, readable from either realm. Nothing here is
-- server-side: the prompt is a client call and the button is a client icon.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Boil = require(ReplicatedStorage.Shared.Boil)

return {
	-- Which of Roblox's two flows the prompt opens.
	--
	-- `Feedback` is "tell the creator what you think", which is what a button
	-- labelled Feedback should open. `PlayerSupport` is the support route — the
	-- one for a player who needs help rather than one who has an opinion — and
	-- putting that behind this icon would send bug reports somewhere the creator
	-- never reads them.
	TYPE = Enum.FeedbackType.Feedback,

	-- The topbar icon. A shared UI icon rather than an uploaded asset, so the
	-- feature installs with no Studio work; swap in an `rbxassetid://` of your own
	-- for artwork that matches the rest of the topbar.
	ICON = Boil.assets.Icons.questionMark,
	-- The word on the button itself. A question mark alone reads as "help" — the
	-- one thing this button doesn't open — so the icon is captioned in place
	-- rather than left to explain itself on hover, which a touch player never
	-- sees at all.
	LABEL = "Feedback",
	-- The tooltip on hover (and on a long press on touch). Says what pressing it
	-- does, since the label already says what it is.
	CAPTION = "Tell the creator what you think",
	-- Which side of Roblox's topbar the icon sits on. Right, beside Roblox's own
	-- controls: this button opens one of *their* panels, and grouping it with the
	-- experience's own buttons on the left would promise a window this game draws.
	ALIGNMENT = "right",
	-- Order within that side. Independent of the left-aligned icons' numbers —
	-- TopbarPlus sorts each alignment separately.
	TOPBAR_ORDER = 1,

	-- Which surfaces this feature renders. Off = the button goes and the feature
	-- is inert, code intact.
	Presentations = {
		topbar = true,
	},
}
