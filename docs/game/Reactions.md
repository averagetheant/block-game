# Reactions

A white bar along the bottom of the screen holding four reactions. Closed by
default — an arrow tab slides it up. Clicking a reaction sends it to **everyone
in the server**: it appears just above the bar, rises, and fades out.

Which four are in the bar is per-player and persisted. Reactions beyond the free
four come from a Store pack, and the Inventory's Reactions tab is where you swap
them in.

## Studio assets

None. Every default reaction is a text glyph, and the one image reaction ships
with a placeholder asset id (`Catalog.luau` § `ROCKET_IMAGE`) — swap it for your
own upload. The point of shipping one image reaction is that the image path is
exercised, not the picture.

## Text and image reactions

A reaction is one or the other:

```lua
{ id = "laugh",  name = "Laugh",  kind = "text",  text = "😂" }
{ id = "rocket", name = "Rocket", kind = "image", image = "rbxassetid://…" }
```

`ReactionGlyph.ui.luau` is the only place that knows the difference — the bar,
the inventory grid and the float layer all render through it, so a third kind
would be one edit rather than three. It's a raw `TextLabel` on purpose: emoji
need the system font, and the gem display font behind `ui.Text` doesn't carry
them (a `ui.Text` emoji renders as tofu).

The float layer fades a **CanvasGroup** rather than the glyph, because
`GroupTransparency` is the one property that fades a TextLabel and an ImageLabel
alike.

## The catalog

`Catalog.luau`. `id` goes over the wire — append, don't rename.

| Reaction | Kind | Pack |
| -------- | ---- | ---- |
| `laugh` 😂, `cry` 😭, `angry` 😠, `question` ❓ | text | free (the default bar) |
| `fire` 🔥, `skull` 💀, `clap` 👏 | text | `reactions.emoji` |
| `rocket` | image | `reactions.emoji` |

`Catalog.DEFAULT_SLOTS` is what a fresh profile's bar holds, in order.

## The Store pack

`Reactions/Store.luau` registers:

- the **`reaction` kind** with `inventory = false`, because equipping a reaction
  means putting it in a bar slot rather than selecting one pack — this feature
  ships its own Inventory tab instead (`ReactionInventoryPresentation`);
- the **Emoji Pack** (`reactions.emoji`), 100 coins.

Coins are TowerGame's currency. If TowerGame were uninstalled the pack would
simply never be affordable — a shop that can't be bought from, rather than one
that errors.

## Packets

| Packet | Direction | Reliability | Payload |
| ------ | --------- | ----------- | ------- |
| `Send` | client → server | unreliable | `{ reactionId }` |
| `Play` | server → all | unreliable | `{ reactionId, userId }` |
| `SetSlots` | client → server | reliable | `{ slots }` — the whole bar |

The glyph never travels. Both ends look the id up in the shared catalog, which
is what stops a client inventing a reaction nobody else can render (or one
nobody bought).

`SetSlots` sends the **whole list** rather than one index: it's four short
strings, and a full list can't get out of step with itself the way a stream of
per-slot writes can. The server validates every entry and rejects the whole list
if any one fails — a half-applied write is a bar that lies.

## Server validation

`ReactionsService` is the only thing that decides whether a reaction is real,
whether the sender owns it, and whether they're allowed to send it yet:

- the id has to be in the catalog;
- if the reaction belongs to a pack, `StoreService.owns` has to say yes;
- at most one reaction per player per `SEND_COOLDOWN` (0.6s).

All three exist because a reaction is a **broadcast**. An unvalidated one is a
client drawing on everyone else's screen; an unthrottled one is a client doing it
sixty times a second.

## Profile slice

```lua
Reactions = { Slots = { "laugh", "cry", "angry", "question" } }
```

Ownership isn't here — which packs were bought lives in the Store's slice, and
that stays true even if a pack is later refunded. `ReactionsController.slots()`
always returns exactly `SLOT_COUNT` valid ids, falling back to the default for a
position whose stored id is missing or unknown, so the bar can't render a hole.

## Client API

```lua
local ReactionsController = require(StarterPlayerScripts.Features.Reactions.ReactionsController)

ReactionsController.slots()                    -- { string }, always SLOT_COUNT long
ReactionsController.owns(reactionId)           -- boolean (asks the Store)
ReactionsController.send(reactionId)
ReactionsController.setSlot(index, reactionId)
ReactionsController.Played                     -- Signal(reactionId, userId)
```

Even your own reaction is drawn from the server's `Play` broadcast rather than
applied locally, so what you see is exactly what everyone else sees.

## Why the bar isn't gem-styled

`ReactionBar.ui.luau` uses raw Frames rather than `ui.Panel` / `ui.Button`. The
bar is deliberately the one flat white surface in the game — that's what makes it
read as a chat affordance rather than another piece of HUD. The shared kit has no
neutral surface primitive, and adding one would be a skin-contract change for a
single call site. Every colour and radius is named in `Constants.luau` rather
than inlined, so it's still tunable in one place.

## Performance

`ReactionFloat.ui.luau` splits ownership: React owns *which* floats exist,
TweenService owns *where* each one is. A float lives for a couple of seconds, so
driving its position from state would re-render the layer every frame for the
whole flight; here the tree changes only when a reaction starts or finishes.
`FLOAT_MAX` (24) caps the simultaneous count — past it the oldest is dropped
rather than the newest refused, so a busy server keeps showing the most recent
mood.

## Constants worth knowing

`Reactions.Constants` (`src/features/Reactions/Constants.luau`):

| Key | Default | What it controls |
| --- | --- | --- |
| `SLOT_COUNT` | `4` | Reactions in the bar. Safe to change — Reconcile fills, the bar clamps. |
| `SEND_COOLDOWN` | `0.6` | Minimum seconds between one player's reactions. |
| `BUTTON_SIZE` / `BAR_PADDING` / `BAR_CORNER` | `62` / `12` / `18` | Bar geometry. |
| `SLIDE_TWEEN_INFO` | `0.28s Quad Out` | The open/close slide. |
| `BAR_COLOR` / `BUTTON_COLOR` / `OUTLINE_COLOR` | white-ish | The bar's palette. |
| `FLOAT_SECONDS` / `FLOAT_RISE` | `2.4` / `0.55` | How long a reaction lives and how far up it travels (scale). |
| `FLOAT_SPREAD` / `FLOAT_DRIFT` | `0.18` / `0.06` | Horizontal start spread and sideways drift, rolled per reaction. |
| `FLOAT_MAX` | `24` | Cap on simultaneous floats. |
| `Presentations.bar` / `.inventory` | `true` | The bar + float layer, and the Inventory tab. |

## Priority

`ReactionsService.Priority = 15` — after PlayerData (1) and Store (10), because
ownership is a Store read.

## Stories

- `ReactionBar.story.luau` — toggle the arrow; switch `slots` to the pack set to
  see three emoji and one image reaction side by side.
- `ReactionFloat.story.luau` — a local Signal fires on a timer so the rise, fade
  and fan-out are visible without a second player.
- `ReactionInventory.story.luau` — slot assignment is real; ownership is a control.
