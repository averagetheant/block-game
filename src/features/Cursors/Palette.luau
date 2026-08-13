--!strict
-- What colour a player's cursor is.
--
-- Derived from the user id rather than assigned by the server, which buys three
-- things at once: the colour costs no bytes, every client agrees on it without
-- being told, and a player who rejoins gets the same colour they had before.
--
-- The hue is a hash rather than `math.random(seed)` — Luau's generator is
-- shared global state, so seeding it here would perturb every other roll in the
-- game (which piece spawns next, which zone comes up) as a side effect of
-- drawing a cursor.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Features.Cursors.Constants)

local Palette = {}

-- Golden-ratio conjugate. Multiplying by it and taking the fraction spreads
-- consecutive ids (which Roblox hands out in blocks, so friends who signed up
-- together have near-identical numbers) across the whole wheel instead of
-- clustering them into one shade.
local GOLDEN_RATIO_CONJUGATE = 0.618033988749895

function Palette.hueFor(userId: number): number
	return (userId * GOLDEN_RATIO_CONJUGATE) % 1
end

function Palette.colorFor(userId: number): Color3
	return Color3.fromHSV(Palette.hueFor(userId), Constants.SATURATION, Constants.VALUE)
end

return Palette
