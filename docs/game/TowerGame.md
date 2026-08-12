# TowerGame

A Tricky Towers-style co-op stacker. Everyone plays **one shared tower**: players
take turns, each turn hands the holder a tetromino they can slide and rotate, and
a 20-second clock drops it for them if they dither. Over the top of that runs the
**storm** — a stage clock demanding a target height, which pays out a permanent
floor when the players make it. The camera never orbits; it rides the tower's
altitude.

Prototype status: the turn loop, the physics, the storm stages, the height
tracking and the saved leaderstats all work end-to-end. There's no win/lose state
and no scoring (see [Not built yet](#not-built-yet)).

## The loop

1. `TowerService` builds the arena (base platform) at server start.
2. Players enter a round-robin `queue` on join.
3. **Turn** — the holder gets a piece spawned `SPAWN_CLEARANCE` studs above the
   current tower top, and `TURN_SECONDS` (20) on the clock.
4. The holder steers (continuous left/right) and spins (quarter turns). The piece
   is an *anchored, server-owned Model*, so every player watches the same aim with
   no transform packets involved.
5. **Drop** — on the holder's release, or when the clock expires, or if the holder
   leaves, the piece is unanchored and physics takes it.
6. `SETTLE_SECONDS` later the next player is up.

Height is recomputed every `POLL_INTERVAL` from every **settled** block (a block
counts once its assembly is slower than `SETTLED_SPEED`, so a piece mid-fall can't
spike the readout) plus every checkpoint platform. `maxHeight` is the running
maximum.

## The storm

The pressure mechanic, running independently of whose turn it is.

- Each stage names a `targetHeight` and a `STORM_SECONDS` (300) clock. The first
  checkpoint is `STORM_FIRST_TARGET` (60 studs) up, and every cleared stage puts
  the next one `STORM_GAP_GROWTH` (5) studs further than the last gap — 60, 65,
  70, and so on.
- **Cleared** — the moment the tower reaches the target, a checkpoint platform is
  welded onto the tower at exactly that altitude, the floor count goes up, and the
  next target is set to *the height they actually reached* plus the new gap.
  Overshooting doesn't make the next stage free.
- **Expired** — the storm takes everything. See [When the storm lands](#when-the-storm-lands).
- On an empty server the clock is held rather than ticking down to nothing.

A checkpoint platform is the same `PLATFORM_SIZE` as the starting base, anchored,
and enters with a two-part tween: it stretches out from a sliver at the center
line while glowing white (Neon), then cools from white to near-black before
dropping back to SmoothPlastic. Because the part is anchored, tweening `Size`
grows it evenly about its center instead of dragging one face.

**Clearing a stage wipes the tower underneath it.** Every block whose highest
point is at or below the new platform is destroyed, so the checkpoint becomes a
clean foundation hanging in the air rather than the cap on a growing pile. That's
what keeps a long session from dragging hundreds of physics parts behind it, and
the height readout doesn't flinch because the platform's own top is what the
measurement lands on. A piece still falling *above* the line survives.

Checkpoints are tracked in their own list, separate from `blocks` — they have no
physics but still count toward the tower's top. Earlier platforms are left where
they are, so the floors you've cleared stay visible below.

## Aiming

Aiming is **client-owned and server-validated**. The holder's client runs the
whole feel of it; the server decides whether the result is legal.

The problem this solves: the piece is a server-owned Model, so moving it means a
round trip and the holder watches their own input arrive late. The fix is the
standard one — `TowerAimController` renders a **local preview clone** that follows
input at frame rate and hides the real piece for that one client:

| Who | Sees | Updated |
| --- | ---- | ------- |
| holder | local preview clone | every frame |
| everyone else | the real server piece | `AIM_INTERVAL` (30/s) |
| server | the real piece | on each `Place`, clamped |

Hiding uses `LocalTransparencyModifier`, which is render-side — the server never
sees it and no other player is affected. Two things about that property cost real
debugging time, so don't "simplify" either away:

- **It doesn't stick.** Something resets it, so the hide is re-applied from the
  render loop rather than set once.
- **It doesn't reset itself either.** The hide has to be explicitly undone in
  `teardown`. Relying on an automatic reset is what once left the first block of
  every round permanently invisible.

The other half of that same bug: the server **clears `HELD_ATTRIBUTE` on release**.
The holder's client finds "its" piece by that attribute, so a released block that
still carried it got re-adopted on the next turn — hidden, and puppeted by the
preview for the rest of the round. `findOwnPiece` additionally requires the model
to be anchored, since a held piece always is and a live physics block never is.

A placement is fully described by an X and a quarter-turn count, so there's no
"move left" packet. `Release` carries the final placement with it, which is what
makes the drop land exactly where the holder saw it rather than wherever the last
stream update reached.

Two input schemes feed the same local state and don't fight:

- **Holding a direction** (all devices) — integrated locally at `STEER_SPEED`.
- **Pointing** (PC) — `TowerPointerController` casts the mouse onto the play plane
  every frame the mouse moves, with no throttle (it only writes a local number;
  the aim controller decides how often the *server* hears). It only speaks while
  the mouse is actually moving, so a keyboard player is never overridden, and its
  baseline resets between turns so a piece never snaps to a stale cursor.

Click-to-drop checks `gameProcessed`, so clicking the HUD's own buttons doesn't
also release the piece.

Nothing here is authoritative. `TowerService.applyPlacement` clamps X to
±`STEER_LIMIT_X` and turns to `% 4` on every message, so "the client owns the
feel" never becomes "the client owns the game".

## Blocks: skins and types

Every piece rolls two independent things at spawn.

Colour is **not** one of them: every piece rolls its own random hue at a fixed
saturation and value, so blocks are vivid and varied without any coming out
muddy. Shape is read from silhouette, not colour.

**Skins** (`BlockSkins.luau`) are pure flavour — a material and the sounds it
makes. They come from the ASMR kit in the place, so the asset ids there
are ones that kit actually ships; don't invent new ones without checking they
resolve, or a skin goes silent.

| Skin | Look | Lands like |
| ---- | ---- | ---------- |
| Classic | Concrete, grey | a dry knock |
| Needoh | Glass, pink | squish, plus a release beat as it settles |
| Butter | SmoothPlastic, yellow | softer squish, same settle beat |
| Glow | Neon, cyan | a bubble pop |

Skins change **material and color only, never geometry**. The kit's meshes are
lovely but they aren't cubes, and a tetromino cell has to be a cube for the
stacking to read honestly — the squish is carried entirely by the sound. Impact
volume scales with the speed the block was travelling, sampled *before* the
collision damps it (a `Touched` handler reading velocity would report a block
that has already stopped), and pitch is randomized per hit so a tower of one skin
doesn't sound like a machine.

**Types** (`BlockTypes.luau`) are the hazard, and they get likelier the further a
run has gone:

```
chance = min(BASE_CHANCE + PER_CHECKPOINT × checkpoints, MAX_CHANCE)
       = min(0.08 + 0.06 × checkpoints, 0.45)
```

- **Explosive** — detonates on impact and consumes itself. Pieces are held
  together by `WeldConstraint`s, which an `Explosion` doesn't break, so it throws
  the tower around without dissolving blocks into loose cells.
- **Glue** — welds to everything it's resting against when it **settles**, not
  when it first touches something. That distinction is the whole mechanic: at the
  moment of impact a block is often still mid-bounce with nothing but the part it
  just grazed nearby, so welding then glues it to the wrong thing (or to nothing).
  Welding to an anchored platform effectively anchors it, which is what glue
  should feel like.

A special block is marked with a `Highlight` in its type's color rather than by
repainting it — the skin already owns the color.

Three edge cases the input controller handles, all of which come from "held" being
a state rather than an event:

- **Two keys at once** — releasing one resumes the other, rather than stopping dead.
- **Lost key-up** (alt-tab mid-glide, gamepad unplugged) — `WindowFocusReleased`
  force-releases, otherwise the piece would slide to the travel limit.
- **Already holding when the turn starts** — no input event fires for a key that
  never moved, and the server clears the steer direction on every new turn, so the
  controller re-asserts what's held when the piece becomes ours.

Touch is the exception: a tap has no key-up, so the HUD buttons send a fixed
`TOUCH_NUDGE_SECONDS` pulse — one tap is worth about
`STEER_SPEED × TOUCH_NUDGE_SECONDS` studs of glide.

## Stats and saving

`Blocks Placed` and `Biggest Height` show on the in-game leaderboard and persist
across sessions.

- `PlayerData.luau` registers the `TowerGame` profile slice through the standard
  discovery convention — PlayerData never mentions this feature.
- `TowerStatsService` owns the reads and writes and mirrors them into a
  `leaderstats` folder. The profile is the truth; the leaderstats values are
  display mirrors (the height column is floored to an integer, the profile keeps
  the decimals).
- Every write goes through `PlayerDataService.SetValue`, so it lands in the replica
  *and* the next autosave.
- `Biggest Height` credits **everyone in the server** when the tower sets a
  record — it's one shared tower, so it's a shared achievement.

Note: in Studio, ProfileStore reports "Roblox API services unavailable - data will
not be saved" unless you enable *Studio Access to API Services* in Game Settings.
The stats still count in-session; they just don't persist.

## Why it plays in 2D

Roblox has no 2D physics mode, so the plane is enforced by hand. Every block lives
at `PLANE_Z` and `TowerService.clampToPlane` runs on Heartbeat: it zeroes
out-of-plane velocity, keeps only in-plane (Z-axis) spin, and nudges back any
assembly that drifts more than `PLANE_TOLERANCE`. Sleeping assemblies are skipped
so a resting tower isn't woken every frame. Pieces still tip and topple — just
sideways, toward the camera plane, the way Tricky Towers does.

A piece is one Model of welded cells with **no PrimaryPart**, deliberately: when a
model has a PrimaryPart, `PivotTo` uses that part's CFrame and ignores
`WorldPivot`, which would swing a rotating piece around its first cell instead of
spinning it in place.

## Studio setup

**None required** — the server generates the base platform on first run. Two
optional hooks:

- **Your own platform.** Build a part in Studio and give it the CollectionService
  tag **`TowerBase`**. The server uses it instead of generating one and measures
  the tower from its top surface. (Server-side only: runtime `AddTag` does *not*
  replicate, which is why the client camera reads the `BaseTopY` attribute the
  server writes on the `TowerArena` folder rather than looking for the tag.)
- **Streaming.** New places ship with `StreamingEnabled` on, and this game
  disables characters — so nothing would give the client a replication focus and
  the player would see a live HUD over an empty sky. `TowerService` sets
  `player.ReplicationFocus` to the base on join. Turning `StreamingEnabled` off in
  Workspace works too, and makes that line redundant.

`Constants.DISABLE_CHARACTERS` is what turns avatars off (`CharacterAutoLoads`).
Flip it to `false` if you want walking players; nothing else depends on it.

## Controls

Every surface calls the same four `TowerController` intents, so adding an input
device is additive.

| Intent | Keyboard / mouse | Gamepad | Touch |
| ------ | ---------------- | ------- | ----- |
| `setSteer(-1)` | hold A / ← | DPadLeft | **LEFT** button (pulse) |
| `setSteer(1)` | hold D / → | DPadRight | **RIGHT** button (pulse) |
| `aim(x)` | move the mouse | — | — |
| `rotate` | W / ↑ / R | ButtonY | **TURN** button |
| `drop` | Space / S / ↓ / left click | ButtonA | **DROP** button |

The HUD shows the matching list in the bottom-left corner for `HINT_SECONDS`
(60), then fades it out — new players get told once, everyone else gets their
screen back.

Keyboard and gamepad are bound in `TowerInputController` through
ContextActionService (one bind covers both). Touch buttons are real skinned
`ui.Button`s in the HUD instead of CAS's generated ones, so mobile matches the
rest of the game's look; `TowerView` renders them only on touch-without-keyboard
devices.

## Files

| File | Realm | Role |
| ---- | ----- | ---- |
| `Constants.luau` | shared | Every tunable + `Presentations` gating |
| `Shapes.luau` | shared | The seven tetrominoes as grid cells (ids are wire-stable) |
| `Packets.luau` | shared | ByteNet: `Place`, `Release`, `State` |
| `BlockSkins.luau` | shared | Look + sounds per skin, with rarity weights |
| `BlockTypes.luau` | shared | Explosive / glue, and the odds curve |
| `PlayerData.luau` | shared | Registers the `TowerGame` profile slice |
| `TowerService.server.luau` | server | Arena, turn queue, held piece, physics, height, storm — the whole authority |
| `TowerStatsService.server.luau` | server | Profile reads/writes + the leaderstats mirror |
| `TowerController.client.luau` | client | State store (`GetData` + `DataChanged`) + the wire |
| `TowerAimController.client.luau` | client | The local preview and everything that makes aiming feel instant |
| `TowerInputController.client.luau` | client | Keyboard + gamepad binds |
| `TowerPointerController.client.luau` | client | Mouse aiming + click-to-drop (PC) |
| `TowerCameraController.client.luau` | client | Scriptable camera riding the tower's altitude |
| `TowerView.client.luau` | client | Container: subscribes via `useReplica`, runs the clocks, picks the device |
| `TowerHUD.ui.luau` | shared | Dumb HUD (turn strip, height, clocks, hint, touch controls) |
| `TurnStrip.ui.luau` | shared | Headshot row, current player centered |
| `ControlsHint.ui.luau` | shared | Bottom-left control list that fades out |
| `TowerHUD.story.luau` | shared | UI Labs story — every prop on a slider, including both clocks |
| `TowerPresentation.client.luau` | client | Registers the HUD as a UIRegistry **root** |

## The HUD

```
                 ( o ) (O) ( o )           turn strip — current player centered
              [ 24.5 studs  best 60.0 ] (◕) height, with the turn clock beside it
              ●────────●────────────○      progress: start, tower, next zone
                   3:42 until storm!
  Move — A / D…        Your turn — T piece            [LEFT][TURN][RIGHT][DROP]
  (fades after 60s)                            $ 1,250   (touch only)
```

The **turn clock is a ring** (`RadialTimer`), sitting beside the height panel and
only existing while someone is aiming — the panel tweens wider to fill the gap
between turns. The ring is drawn by a `UIStroke` on a hollow circle, so the
middle of the dial stays see-through and the gradient cut applies to the ring
itself rather than to a fill that isn't there.

Roblox has no radial fill, and the obvious way to fake one does not work:
**`ClipsDescendants` is ignored on anything inside a rotated ancestor**, so
clipping a circle with a rotated frame silently does nothing and you get a full
circle back. The fix is to put the rotation somewhere that isn't a frame — a
`UIGradient` whose alpha steps hard from opaque to invisible at its midpoint cuts
the disc along a diameter at any angle while every frame stays unrotated. Two
such half-discs, each inside an ordinary (working) half-width clip, intersect
into the wedge. Nothing animates per frame; two gradient rotations change.

The **progress line** (`ProgressLine`) measures *this leg of the climb only* —
from `zoneBaseHeight` (where the current zone started) to `targetHeight` — so a
run always begins at the left dot no matter how tall the tower already is. The
tower is a dot for now; it's a separate element rather than a bar fill precisely
so it can grow into a little stack later.

The status line lives at the **bottom**, where the player is already looking when
they're about to place, and lifts clear of the touch controls when those show.

The turn strip positions each headshot by its offset from the current player
rather than through a layout, so the row *slides* around the current player as
turns cycle instead of re-flowing. `order` arrives current-player-first and the
strip rotates it so the holder lands mid-list — which puts whoever just played on
the left and the upcoming queue on the right.

Boil's demo surfaces are switched off rather than deleted, via each feature's own
`Presentations` flag: `UIShowcase` (the left sidebar and the window frames it
hosts, including the Notes and Settings windows) and `HealthSystem` (the HP
badge). Flip either flag back on to get them back; their UI Labs stories still
work regardless.

## Packets

`State` is broadcast on change, not on a tick, and carries `turnEndsAt` as a
`workspace:GetServerTimeNow()` stamp — clients run the countdown locally rather
than being fed a per-second packet. It re-sends at least once a second so a late
joiner picks up the game without a request/response handshake.

The client's turn check in `TowerController` is a traffic optimization only;
`TowerService` re-validates the holder on every intent.

## Tuning

Everything is in `Constants.luau`. The knobs worth reaching for first:

| Constant | Effect |
| -------- | ------ |
| `TURN_SECONDS` | The drop clock (20) |
| `SETTLE_SECONDS` | Pause between turns |
| `STEER_SPEED`, `STEER_LIMIT_X` | How fast a piece slides and how far off-center it can get |
| `SPAWN_CLEARANCE` | Drop height above the tower top |
| `STORM_SECONDS` | The stage clock (300) |
| `STORM_FIRST_TARGET`, `STORM_GAP_GROWTH` | First checkpoint at 60 studs, each next gap 5 further |
| `STORM_BLAST_*` | How hard the storm throws the tower, and how long the debris flies |
| `BlockTypes.BASE_CHANCE` / `PER_CHECKPOINT` / `MAX_CHANCE` | How often a block is special. **Note the cap** — raising `BASE_CHANCE` alone does nothing past `MAX_CHANCE` |
| `IMPACT_MIN_SPEED`, `IMPACT_LOUD_SPEED` | What counts as a landing, and what counts as a hard one |
| `AVATAR_*` | Turn-strip sizing, spacing and fade |
| `HINT_SECONDS`, `HINT_FADE_SECONDS` | How long the controls list stays, and how fast it goes |
| `PLATFORM_SIZE` | Size of the base *and* every checkpoint — they're the same slab |
| `PLATFORM_GROW_SECONDS`, `PLATFORM_FADE_SECONDS` | The checkpoint entrance tween |
| `BLOCK_PHYSICS` | Friction / density / bounce of every block |
| `CAMERA_DISTANCE`, `CAMERA_AIM_LIFT`, `CAMERA_LERP` | Framing and follow feel |
| `DESPAWN_BELOW` | How far under the platform a fallen block is cleaned up |

The HUD is a full-screen gameplay surface, so it hugs the top and bottom edges
rather than following the centered-by-default rule for feature UIs — centering a
height readout would put it on top of the tower the player is aiming at.

## Zones

Clearing a checkpoint moves the run into a new zone. The server picks it and
broadcasts the id; the server owns the half that can't be faked (how blocks
*feel*), the client owns the look. Both read the same `Zones.luau` table.

| Zone | Blocks | Weather |
| ---- | ------ | ------- |
| Clear Skies | unchanged | a random sky from `Assets.Zones.Normal` |
| Retro | old stud look (Plastic + Studs/Inlet) | — |
| Snowy | slippery (friction 0.05) | snowfall |
| Stormy | unchanged | rain, plus a wind that leans the tower |

Only special zones announce themselves — a normal zone is just a new sky. The
banner clears itself after `ZONE_WARNING_SECONDS`.

Two details worth keeping:

- **Glow blocks are exempt from Retro.** Their whole point is the material, and
  studding them over just makes them grey.
- **The server sends an arbitrary number for the sky, not an index.** It has no
  idea how many skies exist — that's a Studio asset it can't see — so the client
  takes it modulo the folder count. Adding a sky in Studio needs no code change.

The wind is applied as a mass-scaled impulse rather than a velocity write, so
every block leans by the same acceleration and sleeping assemblies wake up and
join in instead of standing rigid through a gale.

All the zone assets live under `ReplicatedStorage.Assets` and are **Studio-
authored — Rojo doesn't sync them**. Every lookup degrades to "leave it as it
was": a missing skybox costs you a nice sky, not the game.

## Cash

| Award | Who | Why |
| ----- | --- | --- |
| 50 per zone reached | everyone | the room cleared it together |
| 10 per five minutes | everyone | one shared clock |
| `CASH_PER_STUD` per stud of new record | whoever placed | they're the one who pushed it up |

The per-stud award pays the last dropper, tracked as `lastDropper`, whenever the
tower's record grows — so extending the tower earns, and the two shared awards
keep it from being purely individual.

There's no cash packet. It's persisted on the profile, so the replica diff *is*
the event: `TowerFeedbackController` watches the value, and an increase becomes
the sound plus a signal the HUD animates from. One source of truth, so the
counter and the flying bills can't disagree about how much arrived.

The bills themselves aren't React-driven — a dozen images moved through state
would re-render the HUD every frame of the burst. React owns the host frame; the
bills are plain instances handed to TweenService that clean up after themselves.

## Sound

| Cue | Who hears it | Where it's fired |
| --- | ------------ | ---------------- |
| `Drop` | everyone, positionally | server, on the released piece |
| `Drop2` | just the dropper | client, in `TowerAimController.drop` |
| `NormalBlockCollision` | everyone | the Classic skin's impact sound |
| `YourTurn` | just you | `TowerFeedbackController` |
| `ZoneReached` | just you | `TowerZoneController` |
| `CashSound` | just you | on the cash value rising |
| `Explosion` | everyone, positionally | on a throwaway marker, since the block is about to be destroyed |

`Sfx.luau` clones from `Assets.Sounds` rather than referencing raw asset ids, so
re-tuning a cue's volume or pitch is a Studio edit and not a code change. A
missing sound warns once and is otherwise a no-op — audio going quiet should
never take gameplay down with it.

Music is **one track per zone**: a zone is the game's chapter, so it's the thing
worth scoring. The track loops until the zone changes rather than handing off
partway through, and the playlist is shuffled (and reshuffled once exhausted) so
a long session doesn't repeat in a fixed order. Client-side, so each player
drives their own. Boil's own Music feature is switched off
(`Music/Constants.ENABLED`) so the two don't fight over the mix.

## When the storm lands

Running out of time ends the run, and it ends it loudly. `breakTower` throws every
block off the play plane — a random horizontal shove, an upward kick, and a
tumbling spin — which is the one moment the game deliberately stops being 2D, so
the wreck scatters instead of sliding sideways. The debris is left flying for
`STORM_BLAST_SECONDS` before it's cleared, because the tower coming apart *is* the
deadline.

Then `resetRun` puts everything back to the start: checkpoints destroyed, floor
count zeroed, gap back to 60, fresh clock.

One thing deliberately survives: **`maxHeight`**. It's the server's best-ever
record rather than part of the run, and `TowerStatsService` has already banked it
into each player's profile. The HUD's "best" is a record; the storm resets the
game, not the history.

## Not built yet

- **No win/lose or scoring.** The tower just grows; collapsing costs nothing.
- **The tower's `maxHeight` is per-server-session** and in memory. Per-*player*
  bests do persist (see [Stats and saving](#stats-and-saving)); a global all-time
  record would need its own DataStore, since it isn't per-player data.
- **No next-piece preview in the HUD.** `nextShapeName` is already plumbed through
  to the component — it just isn't rendered.
- **A very short keyboard tap moves nothing.** Steering is a held state, so a press
  and release inside a single frame nets zero movement. Human taps (50 ms+) move
  about a stud; it only shows up with synthetic input.
- **The tower marker is a plain dot.** `ProgressLine` is built so it can become a
  little stack without touching anything else.
- **Special zones are implemented but unobserved.** Two checkpoints in a row rolled
  normal during testing (a 4-in-10 shot each), so retro / snowy / stormy have not
  been seen end-to-end in a real run. The assets they name all exist and the code
  paths are short, but they haven't been watched. Temporarily zeroing the normal
  zone's `weight` in `Zones.luau` is the quickest way to force one.
- **Skins are colour and material only.** Making a block actually *look* like a
  Needoh means squash-and-stretch on impact, which is a deformation problem the
  cube geometry doesn't allow. The sound carries it for now.
