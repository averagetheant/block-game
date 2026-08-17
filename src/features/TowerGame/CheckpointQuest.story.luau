--!nonstrict
-- UI Labs story for the first-checkpoint quest line.
--
-- It has exactly two states and the second one is, by design, something a player
-- sees once ever — so this is the only place it can be looked at without wiping a
-- profile. Flip `claimed` to see the payoff side.
--
-- Drawn at the HUD's real column width (460) with the column marked out, because
-- the line is wider than that on purpose: it centres on the column and overruns
-- evenly, so the overrun is the thing worth eyeballing here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Features = ReplicatedStorage:WaitForChild("Features")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)

local TowerGame = Features:WaitForChild("TowerGame")
local CheckpointQuest = require(TowerGame:WaitForChild("CheckpointQuest"))
local Constants = require(TowerGame:WaitForChild("Constants"))
local SkinPacks = require(TowerGame:WaitForChild("SkinPacks"))

-- The HUD's top column: the width the line is centred on, and the height of one
-- row at the body tier. Both mirrored from TowerHUD so the story shows the line
-- overrunning by the amount it really does.
local COLUMN_WIDTH = 460
local COLUMN_ROW = 40

local pack = SkinPacks.get(Constants.FIRST_CHECKPOINT_PACK)

return {
	summary = "The first-checkpoint quest line, over the HUD's real column width (outlined). Unclaimed it promises the skin in gold; `claimed` flips it green to the payoff it shows for a few seconds after the grant lands.",
	react = React,
	reactRoblox = ReactRoblox,

	controls = {
		claimed = false,
	},

	story = function(props)
		-- The faint fill *is* the column, marked out so the overrun either side is
		-- visible. Story-only — the real HUD draws nothing behind this line.
		return React.createElement("Frame", {
			Size = UDim2.fromOffset(COLUMN_WIDTH, COLUMN_ROW),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.fromRGB(90, 100, 125),
			BackgroundTransparency = 0.82,
			BorderSizePixel = 0,
		}, {
			-- No size passed: the line sizes itself to the column and its own tier.
			Line = React.createElement(CheckpointQuest, {
				rewardName = if pack then pack.name else "A rare skin",
				rewardExtra = `+{Constants.CASH_PER_ZONE} Coins`,
				claimed = props.controls.claimed,
			}),
		})
	end,
}
