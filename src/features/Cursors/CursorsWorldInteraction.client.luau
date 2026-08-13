-- World presentation for Cursors (seam #4): one small, semi-transparent arrow
-- per remote player, floating on the play plane with their name under it.
--
-- The `WorldInteraction` suffix is load-bearing, not decoration. The client entry
-- discovers exactly three name shapes — `*Presentation`, `*WorldInteraction` and
-- `*Controller` — and anything else is never required at all. So this file wires
-- itself up at require time and has no `Start`, the same as every other world
-- presentation.
--
-- Built imperatively rather than in React, following BlockLabel: these are
-- world-space billboards whose positions change every frame, and driving a
-- per-frame transform through React state would re-render the tree for the whole
-- flight. React owns screens; the world is drawn like this.
--
-- The cursors live in a plain Folder in Workspace, created by the client. That
-- makes them local-only anyway — a client-created instance never replicates
-- upward, so the server has no idea they exist and no other client sees them.
--
-- Workspace rather than `CurrentCamera`, even though the camera is the usual home
-- for local decoration: `CurrentCamera` is swapped out from under you (respawns,
-- Studio handing the camera back), which would orphan the whole folder and leave
-- every cursor frozen wherever it was. Nothing is gained by the camera here. The
-- parts carry `CanQuery = false`, so they stay out of the spatial queries that
-- burning and bombs run over the arena.
--
-- Each cursor eases toward its last reported position instead of snapping. The
-- reports land at SEND_INTERVAL (about 12/s), so without the ease a cursor would
-- visibly step across the screen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Features.Cursors.Constants)
local Palette = require(ReplicatedStorage.Features.Cursors.Palette)
local TowerConstants = require(ReplicatedStorage.Features.TowerGame.Constants)
local assets = require(ReplicatedStorage.Shared.Boil).assets

-- Client-realm sibling.
local CursorsController = require(script.Parent.CursorsController)

if not Constants.Presentations.world then
	return {}
end

local FOLDER_NAME = "PlayerCursors"

type Drawn = {
	part: BasePart,
	-- Where the cursor is being eased toward. Kept beside the part rather than
	-- read back off it, so the ease is driven by the last *reported* position
	-- rather than by wherever the part happened to get to.
	goal: Vector2,
	-- False until the first frame has placed it, so a cursor that has just
	-- appeared starts at its real position instead of gliding in from the last
	-- player who happened to own this slot.
	placed: boolean,
}

local drawn: { [number]: Drawn } = {}
local folder: Folder? = nil

local function container(): Folder
	local existing = folder
	if existing ~= nil and existing.Parent ~= nil then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = FOLDER_NAME
	made.Parent = workspace
	folder = made
	return made
end

-- The name shown under a cursor. A player who hasn't replicated yet gets no
-- label rather than a placeholder — the arrow alone is still useful, and "..."
-- under a cursor reads as a bug.
local function displayName(userId: number): string
	local player = Players:GetPlayerByUserId(userId)
	return if player then player.DisplayName else ""
end

local function build(userId: number): Drawn
	local color = Palette.colorFor(userId)

	local part = Instance.new("Part")
	part.Name = `Cursor_{userId}`
	part.Size = Vector3.one * 0.05
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Locked = true

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Cursor"
	billboard.Size = UDim2.fromScale(Constants.SIZE, Constants.SIZE + Constants.NAME_HEIGHT)
	billboard.SizeOffset = Vector2.new(0, 0)
	-- Studs, so a cursor shrinks with distance like the tower does rather than
	-- staying a fixed pixel size and swelling as the camera pulls back.
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Parent = part

	local icon = Instance.new("ImageLabel")
	icon.Name = "Arrow"
	icon.Size = UDim2.fromScale(1, Constants.SIZE / (Constants.SIZE + Constants.NAME_HEIGHT))
	icon.Position = UDim2.fromScale(0.5, 0)
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.BackgroundTransparency = 1
	icon.Image = assets.Icons.cursor
	icon.ImageColor3 = color
	icon.ImageTransparency = Constants.TRANSPARENCY
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = billboard

	local label = Instance.new("TextLabel")
	label.Name = "PlayerName"
	label.Size = UDim2.fromScale(1, Constants.NAME_HEIGHT / (Constants.SIZE + Constants.NAME_HEIGHT))
	label.Position = UDim2.fromScale(0.5, 1)
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.BackgroundTransparency = 1
	label.Text = displayName(userId)
	label.TextColor3 = color
	label.TextTransparency = Constants.NAME_TRANSPARENCY
	-- Scaled rather than a fixed TextSize: the billboard is measured in *studs*,
	-- so it already shrinks with distance, and a pixel size would fight that —
	-- the name would swell to fill a far-away cursor. The NAME_HEIGHT band is
	-- what makes it small.
	label.TextScaled = true
	label.Font = Enum.Font.GothamMedium
	label.Parent = billboard

	-- Keeps the name legible against a light block without a full stroke pass.
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 1
	stroke.Transparency = 0.5
	stroke.Parent = label

	part.Parent = container()
	return { part = part, goal = Vector2.zero, placed = false }
end

local function clearAll()
	for userId, entry in drawn do
		entry.part:Destroy()
		drawn[userId] = nil
	end
end

-- Bring the drawn set in line with what the controller last heard. Runs on the
-- Changed signal rather than per frame: the *set* only changes when a player
-- joins, leaves or goes idle, while their positions move constantly.
local function sync()
	if not CursorsController.enabled() then
		clearAll()
		return
	end

	local seen: { [number]: boolean } = {}
	for _, cursor in CursorsController.list() do
		seen[cursor.userId] = true
		local entry = drawn[cursor.userId]
		if entry == nil then
			entry = build(cursor.userId)
			drawn[cursor.userId] = entry
		end
		entry.goal = Vector2.new(cursor.x, cursor.y)
	end

	for userId, entry in drawn do
		if not seen[userId] then
			entry.part:Destroy()
			drawn[userId] = nil
		end
	end
end

-- Wired at require time. This runs before CursorsController.Start (controllers
-- load after presentations), which is fine: `Changed` is a module-scope signal
-- that exists as soon as the module body has run, so connecting to it early just
-- means being ready for the first packet.
CursorsController.Changed:Connect(sync)

RunService.RenderStepped:Connect(function(deltaTime)
	-- Framerate-independent exponential ease, the same shape the camera follow
	-- uses, so a cursor and the shot it sits in move alike.
	local alpha = 1 - math.exp(-Constants.FOLLOW_RATE * deltaTime)
	for _, entry in drawn do
		local goal = Vector3.new(
			entry.goal.X,
			entry.goal.Y,
			TowerConstants.PLANE_Z + Constants.PLANE_OFFSET_Z
		)
		if not entry.placed then
			entry.placed = true
			entry.part.Position = goal
			continue
		end
		entry.part.Position = entry.part.Position:Lerp(goal, alpha)
	end
end)

return {}
