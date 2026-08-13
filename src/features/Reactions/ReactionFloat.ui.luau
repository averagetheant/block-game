--!strict
-- The layer reactions fly up. One CanvasGroup per live reaction, rising from
-- just above the bar and fading out on the way.
--
-- React owns *which* floats exist; TweenService owns where each one is. That
-- split matters: a float lives for a couple of seconds, so driving its position
-- from state would re-render the layer every frame for the whole flight. Here
-- the tree only changes when a reaction starts or finishes — a few times a
-- second at worst, even with a full server reacting.
--
-- The fade is on a CanvasGroup rather than the glyph, because a reaction is a
-- TextLabel or an ImageLabel depending on its kind and GroupTransparency is the
-- one property that fades both. It also keeps ReactionGlyph as the single place
-- that knows the difference.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local React = require(ReplicatedStorage.Packages.React)
local Constants = require(script.Parent.Constants)
local ReactionGlyph = require(script.Parent.ReactionGlyph)

export type Props = {
	-- Fires with (reactionId, userId) each time anyone reacts.
	played: any,
}

type Float = {
	key: number,
	reactionId: string,
	-- Horizontal start and end, in scale units across the screen.
	fromX: number,
	toX: number,
}

local RISE_TWEEN = TweenInfo.new(Constants.FLOAT_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- The fade lags the rise: a reaction that starts disappearing immediately never
-- reads. Quadratic in, so most of the fade happens near the top of the arc.
local FADE_TWEEN = TweenInfo.new(
	Constants.FLOAT_SECONDS * 0.8,
	Enum.EasingStyle.Quad,
	Enum.EasingDirection.In,
	0,
	false,
	Constants.FLOAT_SECONDS * 0.2
)

-- One reaction in flight. Renders once, then hands itself to TweenService and
-- reports back when it's done so the parent can drop it.
local function FloatItem(props: { float: Float, onDone: (key: number) -> () })
	local float = props.float
	local groupRef = React.useRef(nil :: CanvasGroup?)

	React.useEffect(function()
		local group = groupRef.current
		if group == nil then
			return
		end

		local rise = TweenService:Create(group, RISE_TWEEN, {
			Position = UDim2.fromScale(float.toX, Constants.FLOAT_START_Y - Constants.FLOAT_RISE),
		})
		local fade = TweenService:Create(group, FADE_TWEEN, { GroupTransparency = 1 })
		rise:Play()
		fade:Play()

		-- The rise is the longer of the two, so it's the one that decides when
		-- the float is over.
		rise.Completed:Once(function()
			props.onDone(float.key)
		end)

		return function()
			rise:Cancel()
			rise:Destroy()
			fade:Cancel()
			fade:Destroy()
		end
	end, {})

	return React.createElement("CanvasGroup", {
		ref = groupRef,
		Size = UDim2.fromOffset(Constants.FLOAT_SIZE, Constants.FLOAT_SIZE),
		Position = UDim2.fromScale(float.fromX, Constants.FLOAT_START_Y),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		GroupTransparency = 0,
		Active = false,
	}, {
		Glyph = React.createElement(ReactionGlyph, {
			reactionId = float.reactionId,
			textSize = Constants.FLOAT_TEXT_SIZE,
		}),
	})
end

return function(props: Props)
	local floats, setFloats = React.useState({} :: { Float })
	-- Monotonic, so a key is never reused while an old float is still unmounting.
	local nextKey = React.useRef(1)

	local onDone = React.useCallback(function(key: number)
		setFloats(function(current: { Float }): { Float }
			local result: { Float } = {}
			for _, float in current do
				if float.key ~= key then
					table.insert(result, float)
				end
			end
			return result
		end)
	end, {})

	React.useEffect(function()
		local connection = props.played:Connect(function(reactionId: string)
			local key = nextKey.current
			nextKey.current = key + 1

			-- Rolled once per reaction so a burst fans out instead of stacking
			-- into a single column.
			local fromX = 0.5 + (math.random() * 2 - 1) * Constants.FLOAT_SPREAD
			local toX = fromX + (math.random() * 2 - 1) * Constants.FLOAT_DRIFT

			setFloats(function(current: { Float }): { Float }
				local result = table.clone(current)
				table.insert(result, { key = key, reactionId = reactionId, fromX = fromX, toX = toX })
				-- A full server all reacting at once is what this guard is for:
				-- past the cap the oldest is dropped rather than the newest
				-- refused, so the screen keeps showing the most recent mood.
				while #result > Constants.FLOAT_MAX do
					table.remove(result, 1)
				end
				return result
			end)
		end)
		return function()
			connection:Disconnect()
		end
	end, { props.played } :: { any })

	local children: { [string]: any } = {}
	for _, float in floats do
		children[`Float{float.key}`] = React.createElement(FloatItem, {
			float = float,
			onDone = onDone,
		})
	end

	return React.createElement("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
	}, children)
end
