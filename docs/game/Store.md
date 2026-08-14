# Store

The shop, the inventory, and the ownership both read. Two windows off the left
rail: **Shop** (spend coins or Robux) and **Inventory** (equip what you own).

Store ships **no content**. It owns the mechanism — a currency balance it debits,
an owned set, one equipped slot per kind, the two windows, and the single
`ProcessReceipt` callback Roblox allows per game. Every pack, currency, product
and gamepass is declared by the feature that owns it, in a sibling `Store.luau`
that Store's auto-discovery loop picks up on both realms.

## Studio assets

None in code, but the **developer products and gamepasses must exist on the
place**. A product id that isn't configured makes `PromptProductPurchase` throw.
The ids TowerGame registers are in `TowerGame/Constants.luau` § `PRODUCTS` and
§ `GAMEPASSES`; GamemodeVote's one pass is `GAMEPASS_DOUBLE_VOTE` in its own
Constants. A gamepass registered with id `0` is a placeholder — the Buy button
declines politely instead of prompting.

## Packets

`Store/Packets.luau` — two, both client → server:

| Packet | Payload | What the server does |
| ------ | ------- | -------------------- |
| `Purchase` | `{ packId }` | Looks the pack up, checks it isn't already owned, checks the balance, debits, grants. |
| `Equip` | `{ kind, packId }` | Checks the pack exists, is that kind, and is owned; writes the equipped slot. An **empty `packId` unequips** — "no skin" is a choice, so it has to be sendable. |

Robux purchases don't use a packet: `MarketplaceService`'s prompt is a client
call and the grant arrives on the server as a receipt.

## Profile slice

```lua
Store = {
    Owned    = {},  -- packId → true. Nothing is ever set to false.
    Equipped = {},  -- pack kind → packId. Absent = nothing equipped.
    Receipts = {},  -- granted Robux purchase ids, newest last, capped at 50.
}
```

**Balances are not here.** A currency lives wherever its owning feature keeps it
(coins are `TowerGame.Cash`), and Store is told the *path* rather than given a
copy — see `registerCurrency` below. A second copy would be a second source of
truth.

`Receipts` is what stops a redelivery paying twice: Roblox re-delivers a receipt
until it's acknowledged as granted, so the purchase id has to be remembered.

## Adding content from another feature

Drop a `Store.luau` next to your feature's `init.luau`:

```lua
-- src/features/Pets/Store.luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local assets = require(ReplicatedStorage.Shared.Boil).assets

return function(Store)
    Store.registerKind({ id = "pet", title = "Pets", order = 3 })
    Store.registerPack({
        id = "pets.golden", kind = "pet",
        name = "Golden Pet", description = "It follows you around.",
        icon = assets.Icons.rebirth,
        price = 250, currency = "coins",
        variant = "yellow", order = 1,
    })
end
```

The file loads on **both realms** — the server validates purchases against the
same catalog the client renders — so keep it free of realm-specific code. Use
`Boil.assets` rather than `Boil.ui` for icon ids: `Boil.ui` drags the whole React
kit onto the server for the sake of one string.

The registry **seals** after the discovery pass. A later `register*` errors at
the call site rather than letting the two realms' catalogs drift apart. The one
exception is `registerInventoryTab`, which carries a React element and can only
come from the client.

### The five registrations

| Call | Declares | Notes |
| ---- | -------- | ----- |
| `registerKind{ id, title, order?, inventory? }` | What a pack kind is *called* | One shop tab per kind that has packs. `inventory = false` when your feature ships its own Inventory tab. |
| `registerPack{ id, kind, name, description, icon?, price, currency, variant?, order? }` | A buyable, equippable thing | `id` is persisted — append, don't rename. |
| `registerCurrency{ id, name, icon?, path }` | A soft currency | `path` is the profile path its balance lives at, e.g. `{ "TowerGame", "Cash" }`. Store reads and debits through it. |
| `registerProduct{ id, name, description?, icon?, group, order?, variant?, amount?, currency? }` | A developer product | `group = "currency"` shows it in the Robux tab and grants `amount` of `currency` generically. `group = "action"` keeps it out of the shop entirely — its button lives elsewhere and a **server handler** runs the effect. |
| `registerGamepass{ id, name, description, icon?, order?, variant? }` | A gamepass card | Store sells it and tracks ownership; what it *does* is your feature's server code — see [Gamepasses](#gamepasses). |

### Action products need a server handler

`group = "action"` products do something rather than grant something, and what
they do is server code — so it can't live in the shared `Store.luau`. Register it
from your own service:

```lua
-- src/features/Pets/PetProductsService.server.luau
local StoreService = require(ServerScriptService.Features.Store.StoreService)

PetProductsService.Priority = 25  -- after Store (10)

function PetProductsService.Start()
    StoreService.registerProductHandler(PRODUCT_ID, function(player)
        return grantSomething(player)  -- true = granted
    end)
end
```

Return **false for "not now"**. Store leaves the receipt undelivered, Roblox
re-delivers it, and the player gets what they paid for a moment later instead of
losing it. That's how TowerGame's Nuke declines while a checkpoint cutscene is
running.

`MarketplaceService.ProcessReceipt` is Store's — one callback per game. A second
feature assigning it would silently replace this one and every purchase Store
knows about would stop being granted.

### Gamepasses

A gamepass is bought once and owned forever, which makes it the opposite of a
receipt: there's nothing to grant and nothing to remember. Ownership is Roblox's
answer, so Store *asks* rather than stores it — one
`UserOwnsGamePassAsync` per registered pass when a player joins, and again
whenever a purchase prompt closes over one. Nothing goes on the profile: a
refunded pass has to stop working, and a profile would remember it forever.

```lua
-- Server, in whatever service the perk belongs to:
if StoreService.ownsGamepass(player, MY_PASS_ID) then
    amount *= 2
end
```

`ownsGamepass` is **non-yielding**. It's read from gameplay code — a cash award,
a turn being handed out — and a web call in the middle of a turn isn't something
the game can wait on. The cost is that a pass reads as unowned for the moment
between joining and the query landing, which is the safe direction to be wrong
in; passes that apply per-turn or per-award recover on the next one.

The client has `StoreController.ownsGamepass(id)` plus a `GamepassesChanged`
signal, and that's what turns the shop card from **Buy** into **Owned**. It's for
display: everything a pass actually does is checked again on the server, because
a client saying "I own it" is not a grant.

A pass with id **0** is a placeholder — the Buy button declines politely instead
of prompting, and neither realm asks Roblox about it.

### Registering your own Inventory tab

When "equip" doesn't mean "pick one pack" — Reactions assigns reactions to bar
slots — register a tab from a client presentation:

```lua
-- src/features/Reactions/ReactionInventoryPresentation.client.luau
Store.registerInventoryTab({
    id = "reactions", title = "Reactions", order = 2,
    element = React.createElement(ReactionInventoryView),
})
```

Pair it with `inventory = false` on your `registerKind` call, or the kind gets a
generic tab as well and the window shows the same content twice.

## Client API

```lua
local StoreController = require(StarterPlayerScripts.Features.Store.StoreController)

StoreController.owns(packId)            -- boolean
StoreController.equipped(kind)          -- packId | nil ("no pack" is a real answer)
StoreController.balance(currencyId)     -- number, 0 before the replica arrives
StoreController.canAfford(packId)       -- boolean
StoreController.purchase(packId)        -- intent; the replica diff is the truth
StoreController.equip(kind, packId)
StoreController.unequip(kind)
StoreController.promptProduct(productId)
StoreController.promptGamepass(gamepassId)
StoreController.ownsGamepass(gamepassId)  -- display only; the server asks again
StoreController.GamepassesChanged         -- fires when an answer lands
```

Nothing is applied locally. A rejected request simply never changes anything,
rather than flickering into the bought state and back.

## Server API

```lua
local StoreService = require(ServerScriptService.Features.Store.StoreService)

StoreService.owns(player, packId)
StoreService.ownsGamepass(player, gamepassId)  -- non-yielding; see Gamepasses
StoreService.equipped(player, kind)
StoreService.getBalance(player, currencyId)
StoreService.credit(player, currencyId, amount)
StoreService.grantPack(player, packId)         -- ownership without payment
StoreService.registerProductHandler(productId, handler)
```

`grantPack` is how a pack arrives by any route that isn't buying it — a daily reward, a promo, an admin grant — so ownership is always written through one line instead of each caller reaching into the profile. It declines an unregistered pack (ownership of something no catalog describes can never be rendered or equipped) and treats already-owned as success, so a reward doesn't fail just because the pack was bought yesterday.

## Constants worth knowing

`Store.Constants` (`src/features/Store/Constants.luau`):

| Key | Default | What it controls |
| --- | --- | --- |
| `PROFILE_KEY` | `"Store"` | Top-level profile key. |
| `SHOP_FRAME_ID` / `INVENTORY_FRAME_ID` | `"Shop"` / `"Inventory"` | UIShell frame ids. Open either with `UIShell.useFrame().open(Store.SHOP_FRAME_ID)`. |
| `MAX_PACK_ID_LENGTH` | `64` | Bound on the string a client can make the server hash. |
| `MAX_RECEIPT_HISTORY` | `50` | Purchase ids remembered per profile. |
| `CARD_WIDTH` / `CARD_HEIGHT` / `CARD_GAP` | `236` / `268` / `14` | Grid tile geometry — three per row at the default window width. |
| `Presentations.shop` / `.inventory` | `true` | Turn either window (and its rail entry) off without deleting code. |

## Priority

`StoreService.Priority = 10` — after PlayerData (1), ahead of feature services
that register product handlers. A receipt landing before its handler exists comes
back `NotProcessedYet` and is re-delivered, so the ordering is a nicety rather
than a correctness requirement.

## Stories

`ShopUI.story.luau` and `InventoryUI.story.luau` both require `Features.Store`
(not just the submodules), which is what runs auto-discovery — so they show
whatever the installed features actually registered rather than a mock. Ownership
and balances are UI Labs controls, because in game those come from a replica.
