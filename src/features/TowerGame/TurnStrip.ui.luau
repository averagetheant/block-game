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

local React = require(ReplicatedStorage.Packages.React)
local ui = require(ReplicatedStorage.Shared.Boil).ui
local Constants = require(script.Parent.Constants)

export type Props = {
	-- User ids in turn order, current holder first. Empty between turns.
	order: { number },
	-- 0 when nobody holds a piece; then nobody is highlighted.
	holderUserId: number,
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

		local size = if isCurrent then Constants.AVATAR_SIZE else Constants.AVATAR_SIZE_INACTIVE

		children[`Player{userId}`] = React.createElement("ImageLabel", {
			Image = headshot(userId),
			BackgroundColor3 = Color3.fromRGB(24, 26, 34),
			BackgroundTransparency = if isCurrent then 0.15 else 0.5,
			BorderSizePixel = 0,
			ImageTransparency = if isCurrent then 0 else Constants.AVATAR_FADE_INACTIVE,
			Size = UDim2.fromOffset(size, size),
			Position = UDim2.new(0.5, offset * Constants.AVATAR_SPACING, 0.5, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = if isCurrent then 2 else 1,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
			Stroke = React.createElement("UIStroke", {
				Thickness = if isCurrent then ui.theme.thinStrokeThickness else 1,
				Color = if isCurrent then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(160, 165, 185),
				Transparency = if isCurrent then 0 else 0.5,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
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
