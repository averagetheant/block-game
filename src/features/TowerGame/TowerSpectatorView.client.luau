-- The "Not playing" badge, and the button back into the rotation on it.
--
-- Its own root rather than a child of `TowerAfkView`, and that split is the whole
-- point of the file: the badge draws **behind** the rest of the UI
-- (`ui.layers.underlay`) while the card it used to share a host with draws over
-- everything. Roots are siblings under one `ZIndexBehavior.Sibling` ScreenGui, so
-- a root's own ZIndex is the only thing that decides what covers what — a child
-- can't sit lower than its root, however small its number. Two stacking answers
-- therefore need two roots.
--
-- Why the badge belongs underneath: it is a *state*, up for as long as the player
-- is out, and the thing it would otherwise cover is the HUD they're watching the
-- game through. A standing surface that permanently obscures the game to tell you
-- about the game is worse than the state it reports. The card is the opposite — a
-- moment, with a question in it — and stays on top; see `TowerAfkView`.
--
-- The cost of being underneath, stated plainly: where another root overlaps the
-- badge, that root takes the clicks and the PLAY button is unreachable at those
-- pixels. It sits under the HUD's top column and over open sky, so nothing
-- reaches it today — but "put a control on a surface that is deliberately
-- coverable" is a trade, and Settings remains the route that can't be covered.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ui = require(ReplicatedStorage.Shared.Boil).ui
local Constants = require(ReplicatedStorage.Features.TowerGame.Constants)
local SpectatorNotice = require(ReplicatedStorage.Features.TowerGame.SpectatorNotice)

-- Client-realm sibling (StarterPlayerScripts.Features.TowerGame).
local TowerAfkController = require(script.Parent.TowerAfkController)

return function()
	local spectating, setSpectating = React.useState(TowerAfkController.spectating)

	-- The badge is pinned to the top edge, and the top edge is contested: the root
	-- ScreenGui ignores the GUI inset, so canvas y = 0 is the true top of the
	-- display and Roblox's own topbar — the player-list button among it — occupies
	-- the first ~36 screen pixels of this corner.
	--
	-- The inset is measured in *screen* pixels and everything in here is in canvas
	-- units, so it has to be divided by the viewport scale to mean the same
	-- distance (ScaleLayer documents this conversion). A plain constant can't:
	-- whatever clears the topbar on a monitor is half that on a phone at the 0.5
	-- scale floor, which is the device that reported not seeing this at all.
	local viewportScale = ui.useViewportScale()
	local topInset = GuiService:GetGuiInset().Y / math.max(viewportScale, 0.05)

	React.useEffect(function()
		-- It can change between the first render and this effect, so read once
		-- rather than waiting for a change that may already have happened.
		setSpectating(TowerAfkController.spectating())

		local connection = TowerAfkController.Changed:Connect(function()
			setSpectating(TowerAfkController.spectating())
		end)
		return function()
			connection:Disconnect()
		end
	end, {})

	if not spectating then
		return nil
	end

	-- No transparent full-screen host: this root draws one badge and nothing else,
	-- and a host would be a full-screen frame sitting under the HUD for no reason.
	return React.createElement(SpectatorNotice, {
		position = UDim2.new(0.5, 0, 0, topInset + Constants.SPECTATOR_NOTICE_TOP),
		anchorPoint = Vector2.new(0.5, 0),
		zIndex = ui.layers.underlay,
		onResume = TowerAfkController.resume,
	})
end
