# Reactions

A white vertical column down the right edge of the screen, vertically centred,
holding four reactions. An arrow tab on its left edge slides it in and out.
Clicking a reaction sends it to **everyone in the server**: it appears at the
bottom of the screen and rises past the bar, fading out on the way.

**It starts open for keyboard players and closed for everyone else.** On a PC
the column costs a strip of screen edge nobody is otherwise using, so showing it
saves a click; on a phone that strip is scarce and the buttons sit where the
thumb already rests, so touch keeps the pull-in tab. `ReactionsView` makes the
call once at mount off `UserInputService.KeyboardEnabled` — keyboard wins when a
machine reports several inputs, the same way TowerGame's control hint picks its
starting device. `ReactionBar` itself just takes an `initialOpen` prop; the tab
owns the state from then on.

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
| `party` 🎉, `star` ⭐, `muscle` 💪, `hundred` 💯 | text | `reactions.hype` |
| `facepalm` 🤦, `clown` 🤡, `sleep` 😴, `eyes` 👀 | text | `reactions.salt` |
| `tungTung`, `liriliLarila`, `trippiTroppi`, `tralalero` | image | `reactions.brainrot` |
| `heartPink` 💗, `heartBlue` 💙, `heartGreen` 💚, `heartYellow` 💛 | text | `reactions.hearts` |

Every glyph is a **single emoji codepoint**. The red heart (U+2764) is the
reason the hearts pack is pink/blue/green/yellow: it needs a U+FE0F variation
selector to render in colour and falls back to a flat text glyph without one.

`Catalog.DEFAULT_SLOTS` is what a fresh profile's bar holds, in order.

## The Store pack

`Reactions/Store.luau` registers:

- the **`reaction` kind** with `inventory = false`, because equipping a reaction
  means putting it in a bar slot rather than selecting one pack — this feature
  ships its own Inventory tab instead (`ReactionInventoryPresentation`);
- the packs themselves: **Emoji** (`reactions.emoji`, 100), **Hype**
  (`reactions.hype`, 100), **Salt** (`reactions.salt`, 100) and **Brainrot**
  (`reactions.brainrot`, 150) coins;
- **Hearts** (`reactions.hearts`) with `forSale = false` — day 4 of the [daily
  run](DailyRewards.md) hands it over and that's the only way to it, so it has no
  shop card and the server refuses to sell it (see [Reward-only
  packs](Store.md#reward-only-packs)). It takes the `rainbow` gem variant, being
  the one multicoloured pack.

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
- at most one reaction per player per `SEND_COOLDOWN` (0.2s).

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

## Orientation

The bar stacks **vertically** and hides **horizontally**, and those two have to
be different axes. A column that slid out downward would travel through its own
buttons, and its tab would have to sit on top of the slot nearest the corner
instead of clear of the bar — so the tab lives on the left edge and the column
slides right.

Three things follow from that and have to stay in step:

- `ReactionBar.ui.luau` anchors at `(0, 0.5)` — left edge, vertically centred —
  so only x moves and the column stays centred however many slots it holds.
- `ReactionsView` passes `direction = "right"` to `HideWhenFrameOpen`. Hiding it
  downward would send a right-edge column diagonally off the corner.
- `FLOAT_START_X` puts the floats beside the column rather than at screen
  centre, and `FLOAT_SPREAD` is tight enough that the fan still fits on screen
  from there. They launch from the *bottom* (`FLOAT_START_Y`) and rise past the
  bar rather than out of it — the bar is centred, the reactions are not.

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
| `SEND_COOLDOWN` | `0.2` | Minimum seconds between one player's reactions. |
| `BUTTON_SIZE` / `BAR_PADDING` / `BAR_CORNER` | `52` / `7` / `12` | Bar geometry. `BUTTON_SIZE` is a thumb target, not a pointer one — the column sits where a phone's hand already is. |
| `HANDLE_WIDTH` / `HANDLE_HEIGHT` | `18` / `48` | The arrow tab — tall and narrow, the mirror of what a bottom bar wants. |
| `GLYPH_FIT` | `0.58` | Most of a container an emoji's text size may take. Emoji render taller than their nominal `TextSize`, so a glyph sized to its box gets clipped — every glyph size is derived against this. |
| `SLIDE_TWEEN_INFO` | `0.28s Quad Out` | The open/close slide (horizontal). |
| `BAR_COLOR` / `BUTTON_COLOR` / `OUTLINE_COLOR` | white-ish | The bar's palette. |
| `FLOAT_SECONDS` / `FLOAT_RISE` | `2.4` / `0.55` | How long a reaction lives and how far up it travels (scale). |
| `FLOAT_START_X` / `FLOAT_START_Y` | `0.9` / `0.88` | Where a float launches from, in screen scale — beside the column, near the bottom. |
| `FLOAT_SPREAD` / `FLOAT_DRIFT` | `0.045` / `0.05` | Start spread and sideways drift, rolled per reaction. Tight because the fan has to fit between `FLOAT_START_X` and the right edge: `0.9 + 0.045 + 0.05 = 0.995`. |
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
