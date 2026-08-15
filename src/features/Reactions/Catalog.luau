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
Catalog.HYPE_PACK_ID = "reactions.hype"
Catalog.SALT_PACK_ID = "reactions.salt"
Catalog.BRAINROT_PACK_ID = "reactions.brainrot"
Catalog.HEARTS_PACK_ID = "reactions.hearts"

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

	-- Hype: for when the tower is going well.
	{ id = "party", name = "Party", kind = "text", text = "🎉", pack = Catalog.HYPE_PACK_ID, order = 9 },
	{ id = "star", name = "Star", kind = "text", text = "⭐", pack = Catalog.HYPE_PACK_ID, order = 10 },
	{ id = "muscle", name = "Strong", kind = "text", text = "💪", pack = Catalog.HYPE_PACK_ID, order = 11 },
	{ id = "hundred", name = "Hundred", kind = "text", text = "💯", pack = Catalog.HYPE_PACK_ID, order = 12 },

	-- Salt: for when it is not.
	{ id = "facepalm", name = "Facepalm", kind = "text", text = "🤦", pack = Catalog.SALT_PACK_ID, order = 13 },
	{ id = "clown", name = "Clown", kind = "text", text = "🤡", pack = Catalog.SALT_PACK_ID, order = 14 },
	{ id = "sleep", name = "Sleeping", kind = "text", text = "😴", pack = Catalog.SALT_PACK_ID, order = 15 },
	{ id = "eyes", name = "Eyes", kind = "text", text = "👀", pack = Catalog.SALT_PACK_ID, order = 16 },

	-- Brainrot: the character art the game already ships, as reactions. All four
	-- are images, so a pack that is *entirely* image reactions exists — which is
	-- the case the card preview has to handle without a text fallback.
	{
		id = "tungTung",
		name = "Tung Tung",
		kind = "image",
		image = "rbxassetid://96425337367679",
		pack = Catalog.BRAINROT_PACK_ID,
		order = 17,
	},
	{
		id = "liriliLarila",
		name = "Lirili Larila",
		kind = "image",
		image = "rbxassetid://104842983573914",
		pack = Catalog.BRAINROT_PACK_ID,
		order = 18,
	},
	{
		id = "trippiTroppi",
		name = "Trippi Troppi",
		kind = "image",
		image = "rbxassetid://108224067442222",
		pack = Catalog.BRAINROT_PACK_ID,
		order = 19,
	},
	{
		id = "tralalero",
		name = "Tralalero",
		kind = "image",
		image = "rbxassetid://98753768070862",
		pack = Catalog.BRAINROT_PACK_ID,
		order = 20,
	},

	-- Hearts: one reaction in four colours, which is the point — it's the only
	-- pack whose contents read as a set at a glance, so it's what the daily run
	-- hands over. Every glyph here is a single emoji codepoint, deliberately: the
	-- red heart is U+2764, which needs a U+FE0F variation selector to render in
	-- colour and falls back to a flat text glyph without one, so the set is built
	-- from the four hearts that don't have that problem.
	{ id = "heartPink", name = "Pink Heart", kind = "text", text = "💗", pack = Catalog.HEARTS_PACK_ID, order = 21 },
	{ id = "heartBlue", name = "Blue Heart", kind = "text", text = "💙", pack = Catalog.HEARTS_PACK_ID, order = 22 },
	{ id = "heartGreen", name = "Green Heart", kind = "text", text = "💚", pack = Catalog.HEARTS_PACK_ID, order = 23 },
	{ id = "heartYellow", name = "Yellow Heart", kind = "text", text = "💛", pack = Catalog.HEARTS_PACK_ID, order = 24 },
} :: { Reaction }

-- Every reaction belonging to a pack, in display order. The card preview uses
-- this to draw a pack as its actual contents.
function Catalog.inPack(packId: string): { Reaction }
	local result = {}
	for _, reaction in Catalog.List do
		if reaction.pack == packId then
			table.insert(result, reaction)
		end
	end
	table.sort(result, function(a, b)
		return (a.order or math.huge) < (b.order or math.huge)
	end)
	return result
end

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
