# TowerGame

A Tricky Towers-style co-op stacker. Everyone plays **one shared tower**: players
take turns, each turn hands the holder a tetromino they can slide and rotate, and
a 20-second clock drops it for them if they dither. The camera never orbits — it
rides the tower's altitude. The HUD tracks current height and the best height the
tower has ever reached.

Prototype status: the loop, the physics, the turn queue and the height tracking
all work end-to-end. There's no win/lose state, no scoring, and no persistence
yet (see [Not built yet](#not-built-yet)).

## The loop

1. `TowerService` builds the arena (base platform) at server start.
2. Players enter a round-robin `queue` on join.
3. **Turn** — the holder gets a piece spawned `SPAWN_CLEARANCE` studs above the
   current tower top, and `TURN_SECONDS` (20) on the clock.
4. The holder steers (one cell left/right) and spins (quarter turns). The piece is
   an *anchored, server-owned Model*, so every player watches the same aim with no
   transform packets involved.
5. **Drop** — on the holder's release, or when the clock expires, or if the holder
   leaves, the piece is unanchored and physics takes it.
6. `SETTLE_SECONDS` later the next player is up.

Height is recomputed every `POLL_INTERVAL` from every **settled** block (a block
counts once its assembly is slower than `SETTLED_SPEED`, so a piece mid-fall can't
spike the readout). `maxHeight` is the running maximum.

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
| `moveLeft` | A / ← | DPadLeft | **LEFT** button |
| `moveRight` | D / → | DPadRight | **RIGHT** button |
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
| `TowerService.server.luau` | server | Arena, turn queue, held piece, physics, height — the whole authority |
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
| `STEER_LIMIT_X` | How far off-center a piece can travel |
| `SPAWN_CLEARANCE` | Drop height above the tower top |
| `BLOCK_PHYSICS` | Friction / density / bounce of every block |
| `CAMERA_DISTANCE`, `CAMERA_AIM_LIFT`, `CAMERA_LERP` | Framing and follow feel |
| `DESPAWN_BELOW` | How far under the platform a fallen block is cleaned up |

The HUD is a full-screen gameplay surface, so it hugs the top and bottom edges
rather than following the centered-by-default rule for feature UIs — centering a
height readout would put it on top of the tower the player is aiming at.

## Not built yet

- **No win/lose or scoring.** The tower just grows; collapsing costs nothing.
- **`maxHeight` is per-server-session** and in memory. An all-time record needs a
  DataStore (it's global, so it doesn't belong in per-player PlayerData).
- **No next-piece preview in the HUD.** `nextShapeName` is already plumbed through
  to the component — it just isn't rendered.
- **No "your piece is about to drop" feedback** beyond the timer bar turning red
  under 5 seconds.
