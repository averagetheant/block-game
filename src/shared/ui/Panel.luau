--!strict
-- Panel surface. Two modes:
--   - Dark glass (default): translucent black + white outline. The default
--     surface for HUD windows.
--   - Gem (pass `variant = "red" | "blue" | ...`): the same gem stud
--     background used by Button / Badge — tiled noise + fill gradient +
--     outer black stroke + glow stroke (and optionally shine).
--
-- In gem mode, user children are wrapped in a content Frame at ZIndex 2 so
-- they sit above the GemBackground (at ZIndex 1) without each caller having
-- to set ZIndex themselves.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Assets = require(script.Parent.assets)
local GemBackground = require(script.Parent.GemBackground)
local theme = require(script.Parent.theme)

type Props = {
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	zIndex: number?,
	-- Dark-glass tuning. Ignored in gem mode.
	transparency: number?,
	strokeThickness: number?,
	-- Gem mode. When set, the surface paints the gem stud background instead.
	variant: Assets.VariantKey?,
	hasShine: boolean?,
	tileSize: UDim2?,
	children: { [string]: any }?,
}

return function(props: Props)
	if props.variant then
		local variant = Assets.Variants[props.variant] or Assets.Variants.red
		local fillRotation = if props.variant == "rainbow" then 0 else 90
		local glowRotation = if props.variant == "rainbow" then 0 else 90

		local content: { [string]: any } = {}
		if props.children then
			for k, v in pairs(props.children) do
				content[k] = v
			end
		end

		return React.createElement("Frame", {
			Size = props.size or theme.windowSize,
			Position = props.position or UDim2.fromScale(0.5, 0.5),
			AnchorPoint = props.anchorPoint or Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			LayoutOrder = props.layoutOrder,
			ZIndex = props.zIndex,
		}, {
			BackgroundDeco = React.createElement(GemBackground, {
				fillGradient = variant.fill,
				glowGradient = variant.glow,
				fillRotation = fillRotation,
				glowRotation = glowRotation,
				tileSize = props.tileSize,
				hasShine = if props.hasShine == nil then false else props.hasShine,
			}),
			Content = React.createElement("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Color3.fromRGB(255, 255, 255),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = 2,
			}, content),
		})
	end

	local children: { [string]: any } = {
		-- Opt-out, not opt-in: the outline is what separates dark glass from the
		-- sky behind it, so a panel without one is a deliberate ask.
		UIStroke = if props.stroke == false
			then nil
			else React.createElement("UIStroke", {
				Thickness = props.strokeThickness or theme.strokeThickness,
				-- Mitred corners are the gem look, and they're also what makes a
				-- *rounded* stroke wrong here — a mitre traced round an arc reads
				-- as a wobble. A rounded panel that keeps its outline gets the
				-- round join instead.
				LineJoinMode = if props.rounded then Enum.LineJoinMode.Round else Enum.LineJoinMode.Miter,
			}),
		-- Square by default: the gem surface reads as an edge because of its
		-- outline, not its corner.
		UICorner = if props.rounded
			then React.createElement("UICorner", { CornerRadius = theme.cornerRadius })
			else nil,
	}
	if props.children then
		for k, v in pairs(props.children) do
			children[k] = v
		end
	end

	return React.createElement("Frame", {
		Size = props.size or theme.windowSize,
		Position = props.position or UDim2.fromScale(0.5, 0.5),
		AnchorPoint = props.anchorPoint or Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = props.transparency or theme.glassTransparency,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder,
		ZIndex = props.zIndex,
	}, children)
end
