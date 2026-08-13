# Cursors

Every player's pointer, live on the play plane for the whole room. A small
semi-transparent arrow in that player's colour, their name very small underneath.

It's a presence feature, not a mechanic: nothing about the game reads a cursor,
and losing one costs nothing. That's why almost every decision below leans toward
"cheap and approximate" over "correct and expensive".

## Why world space, not screen space

Cursors are positioned in **world studs on the play plane** (`PLANE_Z`), not in
screen coordinates.

Screen space isn't shared. A phone and an ultrawide disagree about where "the
middle of the screen" is, so a screen-space cursor would point at nothing on
anyone else's monitor. A point on the plane is the same point for everyone — and
it's the space the game is already played in, so a cursor over the third block
from the left is over that block on every screen.

Each client solves the same crossing `TowerPointerController` does for aiming:
cast the pointer into the world, find where it crosses `Z = PLANE_Z`.

## The loop

1. `CursorsController` samples the local pointer every `SEND_INTERVAL` (1/12s)
   and sends a `Move` packet — unless it hasn't moved `SEND_EPSILON` studs, in
   which case it sends nothing.
2. `CursorsService` clamps the position into the play area and stores it with a
   timestamp.
3. On the same cadence the server broadcasts **the whole list** as `State`.
4. Every client drops its own entry and hands the rest to
   `CursorsWorldInteraction`, which eases one billboard per remote player toward
   its last reported position.

Both packets are **unreliable**. A cursor position is only true for the instant
it was sampled; a dropped one is replaced a twelfth of a second later, and
re-sending a stale position would be worse than losing it.

The `State` packet carries the whole list rather than per-player deltas because
it's a handful of floats and a full list can't get out of step with itself — a
client that missed a "player left" delta would keep drawing a ghost. The one
subtlety: the empty list is sent **once** when the last cursor disappears, and
then the server goes quiet. Skipping it entirely would leave every client drawing
whatever the final non-empty packet said.

## You can't see your own

The server broadcasts one list to the room (one packet instead of N), so the
filtering happens on the receiving client: `CursorsController` drops the entry
matching `LocalPlayer.UserId`.

Drawing your own would put a second arrow under the system cursor you're already
looking at, and any lag between them reads as the game being broken.

## Input, per device

Three devices, one answer — a point on the plane.

| Device | How the cursor moves | When there's no cursor |
| ------ | -------------------- | ---------------------- |
| Mouse | Project the pointer onto the plane. | Never — there's always a pointer. |
| Touch | Project the **held finger** onto the plane. | Whenever no finger is down. |
| Gamepad | Right stick integrates a position per frame (`STICK_SPEED`, `STICK_DEADZONE`). | Never — the position persists. |

**The right stick is shared with TowerGame's rotate flick**, so flicking to rotate
also nudges your cursor. That's deliberately left alone rather than arbitrated:
you never see your own cursor, so the only effect is a small jump in what other
players see, and a purely cosmetic pointer isn't worth taking a stick away from
the piece controls. If it ever needs separating, the honest fix is to give the
console cursor the aim point rather than a stick of its own.

Touch is the one that needed a decision: a phone has no hover, so a cursor that
existed at all times would have to sit wherever the last tap landed. Instead the
cursor exists only while a finger is down, and lifting it simply stops the
reports — the server's `STALE_SECONDS` timeout removes it. There is no goodbye
packet.

`gameProcessed` is respected on touch start so a tap on the HUD's own buttons
(DROP, TURN, the reaction bar) doesn't fling the cursor to wherever that button
sits. A drag that *began* on the world isn't dropped when it passes over a
button.

## Colours

Derived from the user id, never sent:

```
hue = (userId * 0.618033988749895) % 1
```

This buys three things at once — the colour costs no bytes, every client agrees
on it without being told, and a player who rejoins gets the colour they had
before.

The golden-ratio conjugate is doing real work. Roblox hands out user ids in
blocks, so friends who signed up together have near-identical numbers; multiplying
by an irrational and taking the fraction spreads them across the whole wheel
instead of clustering them into one shade. Verified: ids `…056` and `…057` come
out blue and green.

It's a hash rather than `math.random(seed)` on purpose. Luau's generator is
shared global state, so seeding it here would perturb every other roll in the
game — which piece spawns next, which zone comes up — as a side effect of drawing
a cursor.

## Drawing

`CursorsWorldInteraction` builds billboards imperatively rather than in React, following
`BlockLabel`: these are world-space objects whose transform changes every frame,
and driving that through React state would re-render the tree continuously. React
owns screens; the world is drawn like this.

The file **must** be named `*WorldInteraction` (or `*Presentation` /
`*Controller`). `src/client/init.client.luau` discovers exactly those three name
shapes; anything else is never required at all, and a renderer that is never
required draws nothing while every other part of the feature looks healthy. This
is how the first version of this feature failed.

The parts live in a plain client-made Folder in **Workspace**. That's local-only
regardless — a client-created instance never replicates upward — so the server
doesn't know they exist and no other client sees them. Workspace rather than
`CurrentCamera` (the usual home for local decoration) because the camera gets
swapped out from under you on respawn, which would orphan the folder and freeze
every cursor. `CanQuery = false` keeps them out of the spatial queries burning
and bombs run over the arena.

Each cursor **eases** toward its last reported position (`FOLLOW_RATE`) rather
than snapping. Reports land about 12 times a second, so without the ease a cursor
would visibly step across the screen. It's the same framerate-independent
exponential the camera follow uses, so a cursor and the shot it sits in move
alike. A cursor appearing for the first time is placed rather than eased, or it
would glide in from wherever the previous owner of that slot left it.

## Settings

Registers `cursors.enabled` ("Player cursors") in an **Interface** category via
the `Settings.luau` discovery convention.

Turning it off hides everyone else's cursors **and stops this client reporting
its own** — a player who opted out of the feature shouldn't still be broadcasting
into it.

## Studio assets

The cursor image is `assets.Icons.cursor`
(`rbxassetid://95026136302607`), registered in `src/shared/ui/assets.luau`. It
came from a `Cursor 64px` Decal staged in Workspace; the id is now in the
registry, so that decal is no longer load-bearing.

## Constants worth knowing

`Cursors.Constants` (`src/features/Cursors/Constants.luau`):

| Key | Default | What it controls |
| --- | --- | --- |
| `SEND_INTERVAL` | `1/12` | How often a client reports, and how often the server broadcasts. |
| `SEND_EPSILON` | `0.15` | Movement below this isn't worth a packet. |
| `LIMIT_X` / `MIN_Y` / `MAX_Y` | `90` / `-50` / `600` | Server-side clamp. A cosmetic must not become a way to draw on the sky. |
| `STALE_SECONDS` | `3` | Drop a cursor that stopped reporting (alt-tabbed, lifted finger, opted out). |
| `SIZE` / `TRANSPARENCY` | `2.2` / `0.35` | Arrow size in studs and how far it fades. |
| `NAME_HEIGHT` / `NAME_TRANSPARENCY` | `1` / `0.45` | The name band under the cursor, in studs. Text is `TextScaled` into it. |
| `FOLLOW_RATE` | `18` | How fast a cursor eases toward its last report. |
| `STICK_SPEED` / `STICK_DEADZONE` | `42` / `0.18` | Gamepad stick. |
| `SETTING_ID` | `cursors.enabled` | The toggle. |
| `Presentations.world` | `true` | The cursors themselves. |

## Priority

`CursorsService.Priority = 40` — a leaf; nothing waits on it.
`CursorsController.Priority = 35`. `CursorsWorldInteraction` has no priority and
no `Start` — like every world presentation it wires itself at require time, which
happens *before* controllers start. That ordering is fine: it connects to
`CursorsController.Changed`, a module-scope signal that exists as soon as the
module body has run, so connecting early just means being ready for the first
packet.

## The dependency

Cursors → TowerGame, one way: it reads `TowerGame.Constants.PLANE_Z` (and
`BASE_POSITION` for where a gamepad cursor starts), because "the play plane" is
TowerGame's idea. Remove TowerGame and Cursors has no plane to sit on.

Cursors → Settings, one way, through the discovery convention — inert if Settings
isn't installed.
