--!strict
-- The turn order, as a row of headshots across the top of the screen.
--
-- The current player is pinned to dead center at full size and full opacity;
-- everyone else shrinks, fades, and sits either side of them by their distance
-- in the queue. Because positions are computed from that offset rather than by a
-- layout, the strip *slides* around the current player as turns cycle instead of
-- re-flowing.
--
-- `order` arrives current-player-first (see Packets.State). Rotating it so the
-- holder lands mid-list puts the player who just went on the left and the
-- upcoming queue on the right — the cycle reads left to right.
--
-- Raw ImageLabels rather than a shared primitive: the UI kit has no avatar
-- component, and an avatar chip is game content rather than a reusable
-- primitive worth adding to the contract.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local React = require(ReplicatedStorage.Packages.React)
local ui = require(ReplicatedStorage.Shared.Boil).ui
local Constants = require(script.Parent.Constants)

-- The Double Turn tag, on the corner of the chip of whoever goes again. Yellow
-- because it's a perk rather than a warning, and the strip is otherwise grey.
local REPEAT_TAG = "2x"
local REPEAT_COLOR = Color3.fromRGB(255, 214, 92)
local REPEAT_WIDTH = 40
local REPEAT_HEIGHT = 26

-- How long a chip takes to grow into (or out of) the active slot.
local CHIP_TWEEN = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
-- Sliding sideways is a different motion to swelling, and reads better linear-ish.
local SLIDE_TWEEN = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

export type Props = {
	-- User ids in turn order, current holder first. Empty between turns.
	order: { number },
	-- 0 when nobody holds a piece; then nobody is highlighted.
	holderUserId: number,
	-- Who has another piece coming straight after this one, because they own
	-- Double Turn; 0 for nobody. Tagged rather than listed twice — the strip is
	-- keyed by user id, so a second entry would be the same chip.
	repeatUserId: number?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
}

-- Roblox resolves this to the player's headshot without a web call from us.
local function headshot(userId: number): string
	return `rbxthumb://type=AvatarHeadShot&id={userId}&w=150&h=150`
end

-- Rotate so the current player sits at the middle index, then hand back the
-- rotated list plus that index. Everything else is positioned relative to it.
local function centerOn(order: { number }, currentIndex: number): ({ number }, number)
	local count = #order
	if count <= 1 then
		return order, currentIndex
	end

	local slot = math.ceil(count / 2)
	local shift = slot - currentIndex
	local rotated = table.create(count)
	for index = 1, count do
		-- Pull from `shift` places back, wrapping — the queue is a cycle, so the
		-- entries that fall off the right re-enter on the left.
		rotated[index] = order[((index - 1 - shift) % count) + 1]
	end
	return rotated, slot
end

-- One headshot. Size, fade and slot are all tweened rather than set, so a turn
-- change *moves* the strip instead of cutting to the next arrangement — the
-- current player swells and clears as the others shrink back and slide along.
--
-- Tweened on the instance rather than through React state: these animate every
-- turn change, and re-rendering the whole HUD for each frame of that would be a
-- lot of work to move a few images.
local function AvatarChip(props: {
	userId: number,
	isCurrent: boolean,
	goesAgain: boolean,
	offset: number,
	layoutOrder: number,
})
	local ref = React.useRef(nil :: ImageLabel?)
	local size = if props.isCurrent then Constants.AVATAR_SIZE else Constants.AVATAR_SIZE_INACTIVE
	local fade = if props.isCurrent then 0 else Constants.AVATAR_FADE_INACTIVE
	local position = UDim2.new(0.5, props.offset * Constants.AVATAR_SPACING, 0.5, 0)

	React.useEffect(function()
		local chip = ref.current
		if chip == nil then
			return
		end

		local grow = TweenService:Create(chip, CHIP_TWEEN, {
			Size = UDim2.fromOffset(size, size),
			ImageTransparency = fade,
			BackgroundTransparency = if props.isCurrent then 0.15 else 0.5,
		})
		local slide = TweenService:Create(chip, SLIDE_TWEEN, { Position = position })
		grow:Play()
		slide:Play()

		return function()
			grow:Cancel()
			slide:Cancel()
			grow:Destroy()
			slide:Destroy()
		end
	end, { size, fade, position, props.isCurrent } :: { any })

	return React.createElement("ImageLabel", {
		ref = ref,
		Image = headshot(props.userId),
		BackgroundColor3 = Color3.fromRGB(24, 26, 34),
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		ImageTransparency = Constants.AVATAR_FADE_INACTIVE,
		-- Rendered at the inactive values; the effect above tweens to the real
		-- ones on mount, so a chip appearing eases in rather than popping.
		Size = UDim2.fromOffset(Constants.AVATAR_SIZE_INACTIVE, Constants.AVATAR_SIZE_INACTIVE),
		Position = position,
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = if props.isCurrent then 2 else 1,
		LayoutOrder = props.layoutOrder,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Stroke = React.createElement("UIStroke", {
			Thickness = if props.isCurrent then ui.theme.thinStrokeThickness else 1,
			Color = if props.isCurrent then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(160, 165, 185),
			Transparency = if props.isCurrent then 0 else 0.5,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		-- "This one is taking two." A shadowed label on the corner of the chip
		-- rather than a Badge: a gem badge at the body text floor is wider than
		-- the chip it would sit on.
		Repeat = if props.goesAgain
			then React.createElement(ui.Text, {
				text = REPEAT_TAG,
				textSize = ui.theme.textSizeRegular,
				weight = Enum.FontWeight.Heavy,
				color = REPEAT_COLOR,
				shadow = true,
				size = UDim2.fromOffset(REPEAT_WIDTH, REPEAT_HEIGHT),
				-- Straddling the bottom edge rather than the corner: a chip is a
				-- circle, and a corner tag on a circle floats off it.
				position = UDim2.new(0.5, 0, 1, 0),
				anchorPoint = Vector2.new(0.5, 0.5),
				zIndex = 3,
			})
			else nil,
	})
end

return function(props: Props)
	local order = props.order
	if #order == 0 then
		return nil
	end

	local currentIndex = table.find(order, props.holderUserId) or 1
	local shown, currentSlot = centerOn(order, currentIndex)

	local children: { [string]: any } = {}
	for index, userId in shown do
		local offset = index - currentSlot
		-- Between turns nobody is the holder, so the strip stays put and simply
		-- highlights no one.
		local isCurrent = props.holderUserId ~= 0 and userId == props.holderUserId
		if math.abs(offset) > (Constants.AVATAR_MAX_SHOWN - 1) / 2 then
			continue
		end

		-- Keyed by user id, not slot, so React keeps the same instance as a player
		-- moves along the strip — which is what lets the chip tween between slots
		-- instead of being torn down and rebuilt in the new one.
		children[`Player{userId}`] = React.createElement(AvatarChip, {
			userId = userId,
			isCurrent = isCurrent,
			goesAgain = props.repeatUserId ~= nil and props.repeatUserId ~= 0 and userId == props.repeatUserId,
			offset = offset,
			layoutOrder = index,
		})
	end

	return React.createElement("Frame", {
		Size = props.size or UDim2.new(1, 0, 0, Constants.AVATAR_SIZE + 8),
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder,
	}, children)
end
