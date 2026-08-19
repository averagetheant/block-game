--!nonstrict
-- UI Labs story for the PVP height rail — the column of faces the match HUD pins
-- down the right of the screen.
--
-- Three things are worth driving here, and none of them can be seen in a live
-- match without waiting out three minutes of one:
--
--   * **The ceiling.** Push `leader` up and watch the scale step: the rail opens
--     at 40 studs and adds 40 whenever the tallest tower gets within 80% of the
--     top, so the pack stays in the middle of the rail instead of squashing into
--     the bottom of it. Then pull `leader` back *down* — the ceiling doesn't
--     follow, by design.
--   * **The pile-up.** Drop `spread` to 0 and every lane sits at the same height,
--     which is every match's first ten seconds. The layout pass holds the faces
--     apart and pushes the stack up off the ground dot rather than letting it
--     fall out of the bottom of the component.
--   * **Your marker.** `you` picks which lane is yours — the lit face, the one
--     carrying the reading in studs, and the end of the green trail. Set it to
--     `spectator` for a player with no lane of their own.
--
-- Note the rail *sorts its own input*: `spread` builds the roster in whatever
-- order it likes and the component still draws it tallest-first.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Features = ReplicatedStorage:WaitForChild("Features")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local UILabs = require(ReplicatedStorage.Packages.UILabs)

local TowerGame = Features:WaitForChild("TowerGame")
local HeightRail = require(TowerGame:WaitForChild("HeightRail"))
local PvpConstants = require(TowerGame:WaitForChild("PvpConstants"))

-- Real-looking user ids, so the headshots resolve to the fallback silhouette
-- rather than to nothing at all.
local USER_IDS = { 1, 2, 3, 4, 5, 6 }

-- Which lane is the local player's, by place. "spectator" is somebody watching
-- with no lane of their own.
local YOU = {
	["leader"] = 1,
	["2nd"] = 2,
	["last"] = -1,
	["spectator"] = nil,
}

-- The rail's own footprint in the HUD, near enough: in game the box is
-- scale-relative and fills the band between the topbar and the corner, which is
-- about this on a 16:9 screen and three or four times it on a portrait phone.
local RAIL_WIDTH = 52
local RAIL_HEIGHT = 456

return {
	summary = "The PVP height rail: a headshot per lane riding a shared scale, yours lit and carrying the only reading in studs. Drive `leader` to watch the ceiling step up, and `spread` to 0 to pile every lane on the ground.",
	react = React,
	reactRoblox = ReactRoblox,

	controls = {
		lanes = UILabs.Slider(4, 1, PvpConstants.MAX_LANES, 1),
		-- The tallest tower on the board. Everything else is spaced below it.
		leader = UILabs.Slider(64, 0, 400, 0.5),
		-- Studs between one place and the next. 0 puts the whole lobby on the
		-- ground, which is the case the layout pass exists for.
		spread = UILabs.Slider(12, 0, 60, 0.5),
		you = UILabs.Choose({ "2nd", "leader", "last", "spectator" }),
	},

	story = function(props)
		local c = props.controls
		local count = math.min(c.lanes, #USER_IDS)

		local byPlace = {}
		for place = 1, count do
			byPlace[place] = {
				userId = USER_IDS[place],
				height = math.max(0, c.leader - (place - 1) * c.spread),
			}
		end

		-- Handed over shortest-first on purpose. The rail sorts its own input, and
		-- a story that fed it already in order would never prove it.
		local entries = {}
		for place = count, 1, -1 do
			table.insert(entries, byPlace[place])
		end

		local place = YOU[c.you]
		if place == -1 then
			place = count
		end
		local you = if place then byPlace[place] else nil

		return React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
		}, {
			Rail = React.createElement(HeightRail, {
				entries = entries,
				youUserId = if you then you.userId else nil,
				size = UDim2.fromOffset(RAIL_WIDTH, RAIL_HEIGHT),
				-- Right of centre rather than dead centre, so the readout hanging
				-- off your marker's left has the room it has in the HUD.
				position = UDim2.fromScale(0.7, 0.5),
				anchorPoint = Vector2.new(0.5, 0.5),
			}),
		})
	end,
}
