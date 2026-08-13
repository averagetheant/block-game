--!strict
-- Every reaction that exists, and which pack (if any) you have to own to use it.
--
-- A reaction is either a glyph or a picture. Both are first-class: the bar, the
-- inventory grid and the float layer all render through the same `kind` switch,
-- so a pack can ship uploaded art without any of them learning a special case.
--
-- `id` goes over the wire — append, don't rename. `pack` is a Store pack id;
-- nil means everyone has it.

export type Kind = "text" | "image"

export type Reaction = {
	id: string,
	name: string,
	kind: Kind,
	-- kind == "text": the glyph itself.
	text: string?,
	-- kind == "image": an rbxassetid://… you uploaded.
	image: string?,
	-- Store pack that grants it. nil = free for everyone.
	pack: string?,
	-- Sort order in the inventory grid.
	order: number?,
}

local Catalog = {}

-- The Store pack the paid reactions belong to. Registered into the Store's
-- catalog by this feature's Store.luau; named here because the reactions
-- themselves have to point at it.
Catalog.PACK_ID = "reactions.emoji"

-- Placeholder art for the one image reaction. Swap for your own upload — the
-- point of shipping one is that the image path is exercised, not the picture.
local ROCKET_IMAGE = "rbxassetid://137349421699691"

Catalog.List = {
	-- The four everyone starts with, and the bar's default order.
	{ id = "laugh", name = "Laugh", kind = "text", text = "😂", order = 1 },
	{ id = "cry", name = "Cry", kind = "text", text = "😭", order = 2 },
	{ id = "angry", name = "Angry", kind = "text", text = "😠", order = 3 },
	{ id = "question", name = "Question", kind = "text", text = "❓", order = 4 },

	-- The placeholder pack. Three glyphs and one image, so both kinds are live.
	{ id = "fire", name = "Fire", kind = "text", text = "🔥", pack = Catalog.PACK_ID, order = 5 },
	{ id = "skull", name = "Skull", kind = "text", text = "💀", pack = Catalog.PACK_ID, order = 6 },
	{ id = "clap", name = "Clap", kind = "text", text = "👏", pack = Catalog.PACK_ID, order = 7 },
	{ id = "rocket", name = "Rocket", kind = "image", image = ROCKET_IMAGE, pack = Catalog.PACK_ID, order = 8 },
} :: { Reaction }

-- What a fresh profile's bar holds, in order.
Catalog.DEFAULT_SLOTS = { "laugh", "cry", "angry", "question" }

local byId: { [string]: Reaction } = {}
for _, reaction in Catalog.List do
	byId[reaction.id] = reaction
end

function Catalog.get(id: string): Reaction?
	return byId[id]
end

-- Sorted, for the inventory grid. Free reactions come first because `order`
-- puts them there — the list is authored in the order it should read.
function Catalog.list(): { Reaction }
	local result = table.clone(Catalog.List)
	table.sort(result, function(a, b)
		local ao = a.order or math.huge
		local bo = b.order or math.huge
		if ao ~= bo then
			return ao < bo
		end
		return a.name < b.name
	end)
	return result
end

return Catalog
