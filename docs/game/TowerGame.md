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

- Each stage names a `targetHeight` and a `STORM_SECONDS` (90) clock.
- **Cleared** — the moment the tower reaches the target, a checkpoint platform is
  welded onto the tower at exactly that altitude, the floor count goes up, and the
  next target is set to *the height they actually reached* plus
  `STORM_TARGET_STEP`. Overshooting doesn't make the next stage free.
- **Expired** — the stage restarts with the same target. See
  [Open design question](#open-design-question).
- On an empty server the clock is held rather than ticking down to nothing.

A checkpoint platform is the same `PLATFORM_SIZE` as the starting base, anchored,
and enters with a two-part tween: it stretches out from a sliver at the center
line while glowing white (Neon), then cools from white to near-black before
dropping back to SmoothPlastic. Because the part is anchored, tweening `Size`
grows it evenly about its center instead of dragging one face.

Checkpoints are tracked in their own list, separate from `blocks` — they have no
physics but still count toward the tower's top.

## Steering

Movement is **continuous, not stepped**. A client sends the direction it's
*holding* (-1 / 0 / 1) and the server integrates the position at `STEER_SPEED`
studs per second inside its Heartbeat, clamped to ±`STEER_LIMIT_X`. Two packets
per swipe, no matter how far the piece travels, and the server stays the only
thing that decides where a piece is.

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

| Intent | Keyboard | Gamepad | Touch |
| ------ | -------- | ------- | ----- |
| `setSteer(-1)` | hold A / ← | DPadLeft | **LEFT** button (pulse) |
| `setSteer(1)` | hold D / → | DPadRight | **RIGHT** button (pulse) |
| `rotate` | W / ↑ / R | ButtonY | **TURN** button |
| `drop` | Space / S / ↓ | ButtonA | **DROP** button |

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
| `Packets.luau` | shared | ByteNet: `Steer`, `Spin`, `Release`, `State` |
| `PlayerData.luau` | shared | Registers the `TowerGame` profile slice |
| `TowerService.server.luau` | server | Arena, turn queue, held piece, physics, height, storm — the whole authority |
| `TowerStatsService.server.luau` | server | Profile reads/writes + the leaderstats mirror |
| `TowerController.client.luau` | client | State store (`GetData` + `DataChanged`) + the four intents |
| `TowerInputController.client.luau` | client | Keyboard + gamepad binds |
| `TowerCameraController.client.luau` | client | Scriptable camera riding the tower's altitude |
| `TowerView.client.luau` | client | Container: subscribes via `useReplica`, runs the countdown |
| `TowerHUD.ui.luau` | shared | Dumb HUD (height / best / blocks, status, timer, touch controls) |
| `TowerHUD.story.luau` | shared | UI Labs story — every prop on a slider, including the clock |
| `TowerPresentation.client.luau` | client | Registers the HUD as a UIRegistry **root** |

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
| `STORM_SECONDS` | The stage clock (90) |
| `STORM_FIRST_TARGET`, `STORM_TARGET_STEP` | The first bar, and how much each cleared stage adds |
| `PLATFORM_SIZE` | Size of the base *and* every checkpoint — they're the same slab |
| `PLATFORM_GROW_SECONDS`, `PLATFORM_FADE_SECONDS` | The checkpoint entrance tween |
| `BLOCK_PHYSICS` | Friction / density / bounce of every block |
| `CAMERA_DISTANCE`, `CAMERA_AIM_LIFT`, `CAMERA_LERP` | Framing and follow feel |
| `DESPAWN_BELOW` | How far under the platform a fallen block is cleaned up |

The HUD is a full-screen gameplay surface, so it hugs the top and bottom edges
rather than following the centered-by-default rule for feature UIs — centering a
height readout would put it on top of the tower the player is aiming at.

## Open design question

**Nothing happens when the storm clock expires** — the stage just restarts with the
same target. The name implies a consequence (weather rolling in, blocks getting
shoved, the bottom of the tower crumbling) but a punishment mechanic wasn't
specified, and guessing wrong there changes how the whole game feels. The hook is
one branch in `updateStorm`; decide the consequence and it goes there.

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
