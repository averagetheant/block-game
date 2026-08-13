# TowerGame

A Tricky Towers-style co-op stacker. Everyone plays **one shared tower**: players
take turns, each turn hands the holder a tetromino they can slide and rotate, and
a 10-second clock drops it for them if they dither. Over the top of that runs the
**storm** — a stage clock demanding a target height, which pays out a permanent
floor when the players make it, blows up everything below it, and moves the run
into a new zone. Roughly one piece in twenty is a *type* — a bomb, a burning
block, a Noob — and every piece wears its own name plate saying which. The camera
never orbits; it rides the tower's altitude, and steps back once a stage to show
off what got built.

Prototype status: the turn loop, the physics, the storm stages, the height
tracking and the saved leaderstats all work end-to-end. There's no win/lose state
and no scoring (see [Not built yet](#not-built-yet)).

## The loop

1. `TowerService` builds the arena (base platform) at server start.
2. Players enter a round-robin `queue` on join.
3. **Turn** — the holder gets a piece spawned clear of the tower (see
   [The held piece](#the-held-piece)) and `TURN_SECONDS` (10) on the clock.
4. The holder steers (continuous left/right) and spins (quarter turns). The piece
   is an *anchored, non-colliding, server-owned Model*, so every player watches
   the same aim with no transform packets involved.
5. **Drop** — on the holder's release, or when the clock expires, or if the holder
   leaves, the piece is unanchored and physics takes it.
6. `SETTLE_SECONDS` later the next player is up.

Height is recomputed every `POLL_INTERVAL` from every **settled** block plus every
checkpoint platform. `maxHeight` is the running maximum.

**Settling is a sustained state, not an instant.** A block is a candidate once its
assembly is slower than `SETTLED_SPEED` *and* `SETTLED_SPIN`, but it only counts
once it has stayed that quiet for `SETTLE_CONFIRM_SECONDS` (0.45). The hold is
load-bearing: a block thrown into the air by a bomb is momentarily motionless at
the top of its arc, and "momentarily motionless in mid-air" used to be enough to
hand the players a checkpoint they hadn't built to. Going back above
`UNSETTLE_SPEED` / `UNSETTLE_SPIN` takes a settled block back out of the count, so
a tower knocked loose stops paying out until it comes to rest again.

A Noob (see [Blocks](#blocks-skins-and-types)) is a block that walks, so it's
excluded from the measurement entirely — otherwise the height would bob every
time it jumped.

## The storm

The pressure mechanic, running independently of whose turn it is.

- Each stage names a `targetHeight` and a `STORM_SECONDS` (300) clock. The first
  checkpoint is `STORM_FIRST_TARGET` (60 studs) up, and every cleared stage puts
  the next one `STORM_GAP_GROWTH` (5) studs further than the last gap — 60, 65,
  70, and so on.
- **Cleared** — the tower reaches the target and the [checkpoint cutscene](#the-checkpoint-cutscene)
  runs. Afterwards the floor count is up and the next target is set to *the height
  they actually reached* plus the new gap; overshooting doesn't make the next stage
  free.
- **Expired** — the storm takes everything. See [When the storm lands](#when-the-storm-lands).
- On an empty server the clock is held rather than ticking down to nothing.

A checkpoint platform is the same `PLATFORM_SIZE` as the starting base, anchored,
and enters with a two-part tween: it stretches out from a sliver at the center
line while glowing white (Neon), then cools from white to near-black before
dropping back to SmoothPlastic. Because the part is anchored, tweening `Size`
grows it evenly about its center instead of dragging one face.

Checkpoints are tracked in their own list, separate from `blocks` — they have no
physics but still count toward the tower's top. Earlier platforms are left where
they are, so the floors you've cleared stay visible below.

## The checkpoint cutscene

Clearing a stage is an event, not a counter going up. `runCheckpoint` takes the
world over for about five seconds:

1. `PHASE.CHECKPOINT` goes out and `checkpointActive` freezes everything else —
   the turn loop parks and the height poll returns early. Whoever was holding a
   piece loses it (their client sees the turn end and tears its preview down on
   its own); they get a fresh turn when play resumes.
2. The camera pulls back to frame the **whole leg** the players just built, from
   `zoneBaseHeight` to `height`, and holds it for `CHECKPOINT_VIEW_SECONDS`.
3. The new platform grows in at the top.
4. **The tower under it is blown apart** — every block whose highest point is at
   or below the platform is thrown clear with a random shove, an upward kick and a
   tumble, and destroyed `CHECKPOINT_BLAST_SECONDS` later. A piece still falling
   *above* the line survives. The checkpoint becomes a clean foundation hanging in
   the air rather than the cap on a growing pile, which is what keeps a long
   session from dragging hundreds of physics parts behind it. The height readout
   doesn't flinch, because the platform's own top is what the measurement lands on.
5. The zone rolls. The gamemode is **not** re-voted here — that belongs to the
   [round break](#the-round-break), so the mode the players picked holds for every
   stage of the round.
6. The stage numbers advance, the camera comes back, and
   `CHECKPOINT_RESUME_SECONDS` later the queue starts again.

**The stage numbers are deliberately advanced last.** `zoneBaseHeight` and
`height` are exactly the pair the client camera frames the wide shot from, so
moving them at the start of the sequence would collapse the shot to nothing. The
server sends no camera cue at all — it says `PHASE.CHECKPOINT` and
`TowerCameraController` decides what that looks like.

Freezing the height poll is also what stops the demolition from clearing the
*next* checkpoint off its own debris.

## The gamemode vote

Between **rounds** the players pick how the next one plays. TowerGame doesn't own
the poll — the [GamemodeVote](GamemodeVote.md) feature does — but it owns the
modes and it's what asks:

- `Gamemodes.luau` is the content: four modes and, for each, a complete set of
  stage numbers. A modifier is a full set rather than a diff, so there's one
  place to look to know how a round will play and nothing compounds across
  rounds. `DEFAULT` is the un-voted round — what the game did before any of this
  existed, and what a skipped vote falls back to.
- `Gamemode.luau` is the registration hook GamemodeVote auto-discovers. It just
  hands the list over, so nothing in TowerGame requires GamemodeVote to register.
- `TowerService.runRoundBreak` calls `GamemodeVoteService.startVote()`, which
  **yields** for the length of the poll, and feeds the winner to `applyStage`.

| Mode | What the next round does |
| ---- | ------------------------ |
| Classic | Nothing. The un-voted numbers, exactly. |
| Tower Rush | Two thirds of the usual storm clock for the same target. |
| Blitz Builder | Half the turn clock. The storm clock is left alone, so shorter turns buy the players *more* attempts, not fewer. |
| Mystery Mode | Special-piece odds ×6. Still capped by `BlockTypes.MAX_CHANCE`, so it's "most pieces", not "all". |

**Classic is always the first panel** (`order = 0`, and nothing else claims it). A
ballot of nothing but twists gives the players no way to decline one; Classic is
that answer, and a fixed position makes it the one panel you can pick without
reading. Its modifier *is* `Gamemodes.DEFAULT` — winning Classic and skipping the
vote have to produce the same round, or one of them is lying.

**The winner holds for the whole round**, across as many checkpoints as the
players clear. `runCheckpoint` deliberately doesn't re-vote: changing the rules
out from under a run in progress is what this placement avoids.

The moment is chosen for what's already true: the round is over, the tower is
wreckage, the queue is parked and the storm clock is frozen (`intermission`), so
the vote has the board to itself and needs no state of its own to get it.

**Both clocks ride in the `State` packet.** The HUD draws them as fractions — the
turn ring against the turn length, the storm bar against the stage length — so a
client reading them off `Constants` would draw the wrong shape for every voted
stage. `applyStage` is the one place that writes `stage` and mirrors those two
numbers into `state`.

## The held piece

A piece the holder is still aiming must not be able to touch the tower. Two rules
enforce that, and both exist because breaking either one let a *placement* wreck
the tower before it was ever dropped.

**It doesn't collide.** `suspendCollision` clears `CanCollide` on every part of a
fresh piece and `release` puts it back. Anchored is not enough on its own: an
anchored *colliding* part is immovable world geometry, so a piece parked over the
tower wedges or shoves whatever is still settling underneath it. The restore is
per part from a saved table rather than a blanket `= true`, because a Noob rig
arrives with its own answer for every limb and accessory — handing a hat collision
turns it into a battering ram.

**It stays above the tower for the whole turn.** The spawn altitude is
`restingTopY() + halfHeight + SPAWN_CLEARANCE`, and each of those three terms is
load-bearing:

- `restingTopY()` is *not* `state.height`. The height readout is the scoring
  number: it counts only blocks that have held still for `SETTLE_CONFIRM_SECONDS`,
  and it skips Noobs entirely so a walking block can't make it bob. Both
  exclusions are correct for scoring and wrong for clearance — a block that landed
  a quarter-second ago and a Noob standing on the parapet are very much in the
  way. `restingTopY` counts every block that is *resting* (`slowSince` is set the
  instant an assembly goes quiet, half a second before `settled` follows), plus
  every checkpoint platform, plus the base. Blocks still tumbling are left out, or
  a piece flung up by a bomb would fire the next spawn into orbit.
- `halfHeight` is the piece's largest half extent, not its current one. Rotating
  about Z swaps width and height, so clearing only the current orientation put a
  flat I-piece inside the tower the moment the holder spun it upright.
- `SPAWN_CLEARANCE` (14) is therefore the *gap under the piece*, not the distance
  to its pivot.

`reseatHeldPiece` re-runs that sum every `POLL_INTERVAL` and lifts the piece when
the tower has grown under it — a Noob climbing onto the parapet, a Clone dropping
its copy in, a knocked block coming to rest higher than it started. It only ever
moves the piece **up**; a piece sinking mid-turn reads as a glitch and would drop
the holder into a gap that has since been filled. The one exception is `resetRun`,
which passes `down = true`: the storm has just taken the entire tower, so there is
nothing left to be clear of.

Only Y is ever touched — X and the quarter turns stay the holder's. The holder's
preview reads the altitude back off the server piece every frame (see
[Aiming](#aiming)) so a mid-turn lift can't desync what they're aiming from what
will actually fall, and `pieceTop` rides the state packet so the
[camera](#camera) can guarantee the piece is on screen.

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

**X is the client's, Y is the server's.** The preview reads its altitude back off
the server piece every frame instead of keeping the one it was handed at setup,
because the server can lift a held piece mid-turn (see
[The held piece](#the-held-piece)). Without that read-back the holder would aim a
piece drawn lower than the one that actually falls.

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

Id 4 is **retired**: it was "Glow", a Neon skin that rolled for free. Neon is a
purchase now (see [Skin packs](#skin-packs)), and a stock skin that already
glowed would have made the thing being sold look like nothing. Ids go over the
wire — append, don't renumber.

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
       = min(0.03 + 0.035 × checkpoints, 0.40)
```

That curve is deliberately stingy at the bottom — 3% on the first floor, about a
fifth by the fifth, capped at two in five. The early floors are where players are
still learning to aim, and a hazard every other piece there reads as noise rather
than as escalation.

| Type | Says | Does |
| ---- | ---- | ---- |
| **Bomb** | Explodes. | Beeps and flashes red three times on impact, then detonates and consumes itself. |
| **Glue** | Glues parts together. | Welds to everything it's resting against, on settle. |
| **Clone** | Duplicates itself. | Drops a plain copy of itself in from `CLONE_RISE` above, on settle. |
| **Bouncy** | Bounces! | Lands with `BOUNCY_PHYSICS` instead of the dead default. |
| **Burning** | Burns blocks, careful! | Arrives alight; chars black over `BURN_SECONDS` (20) and disintegrates, spreading to whatever it touches. |
| **Noob** | Places a Noob. | Replaces the tetromino with a Noob that walks and jumps until something lands on it. |

Details worth knowing:

- **Bomb** — the fuse *is* the mechanic. `BOMB_BEEPS` red flashes with a beep each
  give the room time to see which block is about to erupt, and are short enough
  that nobody can build around it. Pieces are held together by `WeldConstraint`s,
  which an `Explosion` doesn't break, so the blast throws the tower around without
  dissolving blocks into loose cells. Every step of the fuse re-checks that the
  block still exists — a bomb is easily wiped by a checkpoint demolition mid-count.
- **Glue** welds on **settle**, not on first touch. That distinction is the whole
  mechanic: at the moment of impact a block is often still mid-bounce with nothing
  but the part it just grazed nearby, so welding then glues it to the wrong thing
  (or to nothing). Welding to an anchored platform effectively anchors it, which
  is what glue should feel like.
- **Clone** waits for the same moment, so the copy has something solid to land on,
  and nudges the copy `CLONE_OFFSET_X` sideways so it can't balance perfectly on
  its own parent. The copy is deliberately **plain** — a clone that cloned would
  bury the arena inside two turns.
- **Burning** is a *state*, not just a type. `igniteBlock` can be called on any
  block, and it is: `spreadBurn` runs from the height poll (not from `Touched`,
  because a block already resting against its neighbour never fires `Touched`
  again) and lights anything within `BURN_SPREAD_RADIUS`, after a
  `BURN_SPREAD_DELAY` grace so a burning piece doesn't take the whole course it
  landed in with it. A lit block lerps from its own colour to black and fades out
  over the last `BURN_FADE_FRACTION` of its life. The hazard isn't the block, it's
  the hole it leaves.
- **Noob** is the one type that **overrides the model** (`overridesModel` in the
  type table). Instead of tetromino cells the holder aims a Noob rig, and once it
  settles it stops being cargo: `NoobBlock.activate` walks it randomly along X
  (never Z — the plane clamp would fight it) and jumps it at `NOOB_JUMP_CHANCE`.
  Any block landing on it at speed kills it, and it ragdolls and despawns. It's
  excluded from the height, from the zone dressing, and from the plane clamp's
  angular term (it has to be allowed to turn around to face where it's walking).
  The rig is a **Studio asset**; a missing one silently rolls an ordinary block
  instead, so a Noob costs you the joke rather than the turn.

A special block is marked with a `Highlight` in its type's color rather than by
repainting it — the skin already owns the color. `Bouncy` is the one type that
owns its own `CustomPhysicalProperties`; `basePhysics` is what keeps that from
being clobbered when a zone re-dresses the tower (Snowy still wins, because a
slippery zone is the whole point of it).

## Name plates

Every piece wears its own name (`BlockLabel.luau`), a `BillboardGui` sitting
**straight above** the block: the title in bold white, centred, and for a typed
block its one-line description under it in a lighter weight.

```
        Bomb T-Shape
          Explodes.

           ▓▓▓▓▓▓
             ▓▓
```

The title composes as `{Type} {Shape}-Shape`, or just `{Shape}-Shape` for a plain
block, or the type alone for one that overrides the model ("Noob"). `titleFor` is
the single naming authority — the HUD's status line calls the same function, so
the plate and the HUD can't describe the piece differently.

Three things about the implementation:

- **Server-built world UI, not a React screen surface.** It has to sit on the
  block and it has to be the same for everybody, so one server-owned instance
  covers every player and the plate can't disagree between clients. (This is why
  it has no UI Labs story — there's no React component to put in one.)
- **Adorned to an `Attachment` at the model's bounding-box centre.** Adorning the
  root cell instead would drag the plate around the piece as it rotates, because
  the root cell moves within the model.
- **The lift above the block is `StudsOffset` (camera space), not
  `StudsOffsetWorldSpace`.** The world-space one turns with the adornee, which
  swung the plate around the piece as it spun and tumbled. Camera space means
  "above" is above on screen whatever the block is doing. The clearance is
  measured off the piece's *longest* side, because the bounding box is sampled
  once at build time and a quarter turn swaps width for height — an I-piece stood
  on end is 4 tall and 1 wide, and one rotation later a height-based offset would
  put the plate inside it.
- **It's dismissed when the block settles.** The plate is a *piece* affordance,
  not a tower one — fifty blocks wearing fifty of them is a wall of text. The
  holder's own plate is the preview clone's; the real piece's is `Enabled = false`
  locally for that one player, for the same reason its parts are hidden (a GUI is
  out of `LocalTransparencyModifier`'s reach).

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

A Noob is exempt from the **angular** half of that only: it has to be allowed to
turn about Y to face the direction it's walking, and zeroing that would leave it
moonwalking on the spot. The Z terms still pin it to the plane.

A piece is one Model of welded cells with **no PrimaryPart**, deliberately: when a
model has a PrimaryPart, `PivotTo` uses that part's CFrame and ignores
`WorldPivot`, which would swing a rotating piece around its first cell instead of
spinning it in place.

## Studio setup

**None required to boot** — the server generates the base platform on first run,
and every Studio asset below degrades to "leave it as it was" when it's missing.

### Assets to create

All under `ReplicatedStorage.Assets` (Rojo does **not** sync these).

| Asset | What it is | Missing means |
| ----- | ---------- | ------------- |
| `Assets.Noob` | A `Model` with a `Humanoid` and a `HumanoidRootPart` — a classic Noob rig | The Noob type silently rolls an ordinary block instead |

> **The rig must be named exactly `Noob`.** Roblox's Rig Builder inserts one
> called `Dummy`, and `NoobBlock.template()` looks the name up directly — a rig
> that is otherwise perfect but still called `Dummy` fails the lookup, and the
> failure is *silent by design* (a missing rig costs the joke, not the turn). If
> Noobs never appear, check the name before anything else. This is exactly how it
> broke the first time.

| `Assets.Sounds.BombBeep` | A short `Sound`, the bomb's warning beep | The fuse still flashes red, just silently |
| `Assets.Zones.Space` | A `Sky` for the Space zone | Space zone keeps whatever sky was up |

(Plus everything the earlier zones already wanted: `Assets.Zones.Retro` / `Snowy`
/ `Stormy`, `Assets.Zones.Normal.*`, `Assets.SnowParticle`, `Assets.RainParticle`,
and the `Assets.Sounds` library.)

### Optional hooks

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
| `setSteer(-1)` | hold A / ← | left stick, or DPadLeft | **LEFT** button (pulse) |
| `setSteer(1)` | hold D / → | left stick, or DPadRight | **RIGHT** button (pulse) |
| `aim(x)` | move the mouse | — | — |
| `rotate` | W / ↑ / R / scroll wheel | right stick, or ButtonY | **TURN** button |
| `drop` | Space / S / ↓ / left click | ButtonA | **DROP** button |

The HUD shows the matching list in the bottom-left corner for `HINT_SECONDS`
(60), then fades it out — new players get told once, everyone else gets their
screen back. **Which list it shows follows the input the player is actually
using**, not what the machine has: `TowerView.useDevice` starts from capability
and then tracks `LastInputTypeChanged`, because a PC with a controller plugged in
reports both `KeyboardEnabled` and `GamepadEnabled` and would otherwise show
keyboard hints to someone holding a pad. `Focus` and `TextInput` are ignored —
they fire from window focus and the chat bar and say nothing about what's in the
player's hands.

### The thumbsticks

Both sticks are **alternatives** to the D-pad and buttons, which keep working
exactly as before.

- **Left stick — steer.** Analog: `setSteer` takes anything in `[-1, 1]` and the
  render loop integrates it, so a gentle push nudges the piece and a full one
  moves it at `STEER_SPEED`. The value is *clamped, not rounded* — rounding is
  what would throw the analog range away and make the stick behave like a D-pad.
  Below `GAMEPAD_STEER_DEADZONE` the stick reads as centred and control hands
  back to the D-pad on that frame, so releasing the stick doesn't leave the piece
  gliding on the last analog value or stomp a direction still being held.
- **Right stick — rotate.** Rotation is discrete, so this is a *flick*: it fires
  once when deflection crosses `GAMEPAD_ROTATE_THRESHOLD` and won't fire again
  until it falls back under `GAMEPAD_ROTATE_RELEASE`. Without that hysteresis a
  stick held over would spin the piece every frame, and one hovering between the
  two would chatter. Either direction turns the same way, because `rotate` is a
  single quarter turn and every other bind that calls it does the same.

The sticks are the one thing ContextActionService can't express: it delivers a
stick as a stream of Change events, and both of these need frame *state* — an
analog value to integrate, and an edge with hysteresis. They're read from
`GetGamepadState` in one Heartbeat instead. A stick held at a constant angle
fires no events at all, which is why polling is the only correct read.

Keyboard, mouse and the gamepad buttons are bound in `TowerInputController`
through ContextActionService (one bind covers both). Touch buttons are real skinned
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
| `BlockTypes.luau` | shared | The six block types, their descriptions, and the odds curve |
| `BlockLabel.luau` | shared | The world-space name plate, and `titleFor` — the one place a piece is named |
| `NoobBlock.luau` | shared | The Noob rig: build, wander, squash. Server-only in practice |
| `Zones.luau` | shared | The five zones, their skies, and their gravity |
| `PlayerData.luau` | shared | Registers the `TowerGame` profile slice |
| `Gamemodes.luau` | shared | The three votable modes and the stage numbers each one sets |
| `Gamemode.luau` | shared | Registers those modes into GamemodeVote (auto-discovered) |
| `SkinPacks.luau` | shared | The buyable block looks and the material each one forces |
| `Store.luau` | shared | Registers the coins currency, the skin packs and the Robux products into the Store (auto-discovered) |
| `TowerService.server.luau` | server | Arena, turn queue, held piece, physics, height, storm — the whole authority |
| `TowerStatsService.server.luau` | server | Profile reads/writes + the leaderstats mirror |
| `TowerProductsService.server.luau` | server | What the Nuke / Next Checkpoint products actually do |
| `TowerProductsPresentation.client.luau` | client | The two Robux buttons in the rail's "actions" cluster |
| `TowerController.client.luau` | client | State store (`GetData` + `DataChanged`) + the wire |
| `TowerAimController.client.luau` | client | The local preview and everything that makes aiming feel instant |
| `TowerInputController.client.luau` | client | Keyboard + gamepad binds |
| `TowerPointerController.client.luau` | client | Mouse aiming + click-to-drop (PC) |
| `TowerCameraController.client.luau` | client | Scriptable camera riding the tower's altitude, the checkpoint pull-back, and the storm shake |
| `TowerView.client.luau` | client | Container: subscribes via `useReplica`, runs the clocks, picks the device |
| `TowerHUD.ui.luau` | shared | Dumb HUD (turn strip, height, clocks, hint, touch controls) |
| `TurnStrip.ui.luau` | shared | Headshot row, current player centered |
| `ControlsHint.ui.luau` | shared | Bottom-left control list that fades out |
| `StormFade.ui.luau` | shared | The storm's one-shot white-out, played on `PHASE.GAMEOVER` |
| `TowerHUD.story.luau` | shared | UI Labs story — every prop on a slider, including both clocks |
| `StormFade.story.luau` | shared | UI Labs story — replays the white-out on demand |
| `TowerPresentation.client.luau` | client | Registers the HUD as a UIRegistry **root** |

## The HUD

```
                 ( o ) (O) ( o )           turn strip — current player centered
              [ 24.5 studs  best 60.0 ] (◕) height, with the turn clock beside it
              ●────────●────────────○      progress: start, tower, next zone
                   3:42 until storm!
  Move — A / D…        Your turn — Bomb T-Shape       [LEFT][TURN][RIGHT][DROP]
  (fades after 60s)                            $ 1,250   (touch only)
```

The **turn clock is a plain circle** (`RadialTimer`), sitting beside the height
panel and only existing while someone is aiming — the panel tweens wider to fill
the gap between turns. Two radial-fill treatments were tried first — a filling
pie and a hollow ring, both built from `UIGradient` hacks to fake a radial sweep
since Roblox has no native one — and neither read well in practice, so the dial
is a solid circle with the seconds label on top; its colour still shifts red
under `URGENT_SECONDS`.

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
`Presentations` flag: `UIShowcase` (its demo HUD, which used to host the Notes
and Settings windows) and `HealthSystem` (the HP badge). Flip either flag back on
to get them back; their UI Labs stories still work regardless.

The left rail is now the [Sidebar](Sidebar.md) feature's own root presentation
rather than UIShowcase's — features register onto it, so Shop, Bag, Nuke and Skip
all arrive without anything editing anything else.

## Packets

`State` is broadcast on change, not on a tick, and carries `turnEndsAt` as a
`workspace:GetServerTimeNow()` stamp — clients run the countdown locally rather
than being fed a per-second packet. It re-sends at least once a second so a late
joiner picks up the game without a request/response handshake.

The piece in play is described by the pair `shapeId` + `blockTypeId`. A type that
overrides the model sends `shapeId = 0` and is named from the type alone, which is
what lets `BlockLabel.titleFor` produce the same string on the block and in the
HUD from one packet.

`pieceTop` is the top of the piece being aimed, in the same terms as `height`, and
0 when nobody holds one. It exists because the camera can't derive it: a piece
spawns clear of the tower and may be lifted again mid-turn, so its altitude is not
a function of `height` and the client would have to know how tall the piece is to
guess. One float buys the camera a guarantee that the piece is on screen.

`turnSeconds` and `stormSeconds` ride along because a gamemode vote can change
either, and both are denominators for the HUD's clocks.

The client's turn check in `TowerController` is a traffic optimization only;
`TowerService` re-validates the holder on every intent.

## Tuning

Everything is in `Constants.luau`. The knobs worth reaching for first:

| Constant | Effect |
| -------- | ------ |
| `TURN_SECONDS` | The drop clock (10) |
| `SETTLE_SECONDS` | Pause between turns |
| `STEER_SPEED`, `STEER_LIMIT_X` | How fast a piece slides and how far off-center it can get |
| `GAMEPAD_STEER_DEADZONE` | Below this the left stick reads as centred and the D-pad takes over (0.2) |
| `GAMEPAD_ROTATE_THRESHOLD` / `_RELEASE` | The right stick's rotate flick and the hysteresis that stops it repeating (0.65 / 0.35) |
| `SPAWN_CLEARANCE` | Clear air under a fresh piece, measured from its lowest possible point — see [The held piece](#the-held-piece) |
| `STORM_SECONDS` | The stage clock (300) |
| `STORM_FIRST_TARGET`, `STORM_GAP_GROWTH` | First checkpoint at 60 studs, each next gap 5 further |
| `STORM_BLAST_*` | How hard the storm throws the tower, and how long the debris flies |
| `CHECKPOINT_*_SECONDS` | The four beats of the checkpoint cutscene. Total pause is their sum plus `PLATFORM_GROW_SECONDS` |
| `CHECKPOINT_BLAST_*` | How hard the old tower is thrown when the new floor lands |
| `BlockTypes.BASE_CHANCE` / `PER_CHECKPOINT` / `MAX_CHANCE` | How often a block is special. **Note the cap** — raising `BASE_CHANCE` alone does nothing past `MAX_CHANCE` |
| `BOMB_BEEPS`, `BOMB_BEEP_ON/OFF`, `EXPLOSION_VOLUME` | The bomb's fuse and how loud the payoff is |
| `BURN_SECONDS`, `BURN_SPREAD_RADIUS`, `BURN_SPREAD_DELAY` | How long a burning block lasts and how eagerly it passes it on |
| `CLONE_RISE`, `CLONE_OFFSET_X` | Where a Clone's copy drops in from |
| `BOUNCY_PHYSICS` | How much a Bouncy block bounces |
| `NOOB_*` | Walk speed, jump odds, and how long a squashed Noob lies there |
| `SETTLE_CONFIRM_SECONDS`, `UNSETTLE_SPEED/SPIN` | How long a block has to hold still to count, and what knocks it back out |
| `IMPACT_MIN_SPEED`, `IMPACT_LOUD_SPEED` | What counts as a landing, and what counts as a hard one |
| `AVATAR_*` | Turn-strip sizing, spacing and fade |
| `HINT_SECONDS`, `HINT_FADE_SECONDS` | How long the controls list stays, and how fast it goes |
| `PLATFORM_SIZE` | Size of the base *and* every checkpoint — they're the same slab |
| `PLATFORM_GROW_SECONDS`, `PLATFORM_FADE_SECONDS` | The checkpoint entrance tween |
| `BLOCK_PHYSICS` | Friction / density / bounce of every block |
| `CAMERA_DISTANCE`, `CAMERA_AIM_LIFT`, `CAMERA_LERP` | Framing and follow feel on a desktop |
| `CAMERA_DISTANCE_TOUCH`, `CAMERA_AIM_LIFT_TOUCH` | The same two for a phone — see [Camera](#camera) |
| `CAMERA_CHECKPOINT_*` | The wide shot: how slowly it eases, how much headroom, and the floor and ceiling on how far back it goes |
| `CAMERA_PIECE_MARGIN` | Headroom kept above the piece being aimed |
| `CAMERA_MIN_HALF_WIDTH` | Half the play area the camera must show across, on any aspect ratio |
| `DESPAWN_BELOW` | How far under the platform a fallen block is cleaned up |

The HUD is a full-screen gameplay surface, so it hugs the top and bottom edges
rather than following the centered-by-default rule for feature UIs — centering a
height readout would put it on top of the tower the player is aiming at.

## Zones

Clearing a checkpoint moves the run into a new zone. The server picks it and
broadcasts the id; the server owns the half that can't be faked (how blocks
*feel*), the client owns the look. Both read the same `Zones.luau` table.

| Zone | Blocks | World |
| ---- | ------ | ----- |
| Clear Skies | unchanged | a random sky from `Assets.Zones.Normal` |
| Retro | old stud look — Plastic, **studs on all six faces** | — |
| Snowy | slippery (friction 0.05) | snowfall |
| Stormy | unchanged | rain, plus a wind that leans the tower |
| Space | unchanged | `workspace.Gravity` drops to **30** |

Only special zones announce themselves — a normal zone is just a new sky. The
banner clears itself after `ZONE_WARNING_SECONDS`.

**Retro studs every face.** A cube read as a 1962 brick from above and as a
smooth slab from the side, which is worse than not studding it at all, so all six
`SurfaceType`s go to `Studs`.

**Leaving a zone undresses the block again.** `applyZoneLook` has an else branch
that puts the skin's material and smooth surfaces back, because a zone is a
property of the world rather than of whichever zone a block happened to spawn in.
Physics comes from `basePhysics` (the block's own — `BOUNCY_PHYSICS` for a Bouncy
block, otherwise `BLOCK_PHYSICS`) unless the zone is Snowy, which always wins.

**Gravity is the one zone rule that isn't per-block.** The server writes
`workspace.Gravity` from `Zones.gravityOf`, which replicates; every zone but Space
names no gravity and gets `Zones.DEFAULT_GRAVITY` (196.2) back. `resetRun` and
`Start` both set it, so a run never inherits the last one's physics — or the place
file's.

Two more details worth keeping:

- **Zone dressing is the server's word, and it's the same for the whole room.** A
  player who owns a material skin pack overrides it on their own screen only —
  see [Skin packs](#skin-packs). A bought cosmetic can't be allowed to change
  what everyone else sees.
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

### Spending it

Cash is registered with the [Store](Store.md) as the **`coins`** currency, whose
balance lives at `{ "TowerGame", "Cash" }`. Store is told the *path* rather than
given a copy, so there's still one source of truth — `CashService` is the only
thing that pays out, and `StoreService` is the only thing that debits.

## Skin packs

`SkinPacks.luau` lists the buyable block looks. There's one so far:

| Pack | Price | Effect |
| ---- | ----- | ------ |
| `skins.neon` — Neon Blocks | 100 coins | Every block part becomes `Enum.Material.Neon` |

A skin pack overrides the material of **the blocks its owner drops**, including
whatever the current zone had dressed them in — a Retro zone can't dull a neon
block. That override is the product.

It's **server, not local**. The pack rides on the block, so the look a player
bought is one the whole room sees on *their* blocks — it doesn't repaint anyone
else's. `TowerService.beginTurn` reads the placer's equipped pack once (via
`StoreService.equipped`) and carries it on the `Held`, then on the `Block`, for
the life of the piece. Reading it per-frame instead would let a block change look
under the room when its placer swapped packs after dropping it.

Because the pack is a property of the block, it survives everything the server
does to materials afterwards: `applyZoneLook` checks for a pack before it studs a
block over for Retro, and a Clone block inherits the original's pack rather than
reverting to the stock look mid-tower.

Unequipping changes nothing already standing — blocks placed under a pack keep
it. It only affects the next piece the player is handed.

The list is the single source of truth — `Store.luau` builds the shop card from
it and `TowerService` reads the material from it, so the price and the look can't
drift apart. `id` is persisted on the profile: append, don't rename.

## Robux products

Registered by `Store.luau`; ids live in `Constants.PRODUCTS` and must exist on
the place or the purchase prompt throws.

| Product | Id | Group | Effect |
| ------- | -- | ----- | ------ |
| 500 Coins | `3707809246` | currency | Store credits `coins` generically |
| 1000 Coins | `3707809250` | currency | ” |
| 10000 Coins | `3707809258` | currency | ” |
| Nuke | `3707809217` | action | `TowerService.nuke()` |
| Next Checkpoint | `3707809233` | action | `TowerService.clearStage()` |

The three bundles appear as cards in the shop's Robux tab. The two actions never
appear in the shop — `group = "action"` keeps them out — because their button is
a rail entry, registered by `TowerProductsPresentation` into the "actions"
cluster — Nuke on `assets.Icons.nuke`, Skip on `assets.Icons.arrowRightOutline`.

`TowerService.nuke()` routes through the same round break the storm uses when its
clock expires, rather than a parallel teardown: the wreck, the gamemode vote and
the fresh round all behave the way players have already seen them behave. Note
that this means buying a Nuke also puts the next round to a vote.

`TowerService.clearStage()` runs the checkpoint at `state.targetHeight`, not
wherever the tower actually stands — the same full sequence (cutscene, platform,
blast, zone roll) the storm's own "reached the target" path runs, just triggered
without playing the climb out. That's what buying Skip is: the players are paid
the altitude they haven't built to yet, not a floor wherever the tower happened
to stop.

Both handlers **return false while a checkpoint cutscene or a round break is
running**. That isn't
a failure — Store leaves the receipt undelivered, Roblox re-delivers it, and the
player gets what they paid for a moment later instead of losing it. Detonating
the tower under a camera holding a wide shot of it would read as a bug.

## Cmdr commands

Gated by `Presentations.command` and, on top of that, by Cmdr's own username
allowlist (`Cmdr/Constants.luau`) — see [presentations.md](presentations.md).
Registered from `Commands.luau`; the enum arguments (`blockType`, `blockSkin`,
`zoneName`) come from a sibling `CmdrTypes.luau`, auto-discovered by
`CommandRegistry.registerTypes` the same way `Commands.luau` is — see
`src/features/Cmdr/CommandRegistry.luau` for why it isn't named `Types.luau`
(that name is already taken by the pure-Luau-type-export convention).

| Command | Args | Does |
| ------- | ---- | ---- |
| `skipstage` (alias `skiplevel`) | — | `TowerService.clearStage()` — the dev-testing handle on a stage clear |
| `skip` | — | The same call, under the name that reads as "replicate the Skip purchase" |
| `block` | `[blocktype]` `[blockskin]` | Pins the **next** piece's type (default: Normal, i.e. no hazard) and/or skin (default: random) via `TowerService.forceNextBlock` — one-shot, consumed by the next `beginTurn` |
| `zone` | `zoneName` | `TowerService.setZone(id)` — forces the tower straight into a zone, outside the usual "roll one on checkpoint clear" path |
| `givecash` | `player` `amount` | `CashService.award(player, amount)` — the same path zone/interval awards pay through |

## Sound

| Cue | Who hears it | Where it's fired |
| --- | ------------ | ---------------- |
| `Drop` | everyone, positionally | server, on the released piece |
| `Drop2` | just the dropper | client, in `TowerAimController.drop` |
| `NormalBlockCollision` | everyone | the Classic skin's impact sound |
| `YourTurn` | just you | `TowerFeedbackController` |
| `ZoneReached` | just you | `TowerZoneController` |
| `BombBeep` | everyone, positionally | each flash of a bomb's fuse |
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

## Camera

A fixed, level shot of the play plane that rides the tower's altitude. It never
orbits; the only things that change are Y and, once per stage, how far back it
stands.

**Phone framing is its own shot.** A phone held upright has far less vertical room
than a monitor, so the desktop `CAMERA_AIM_LIFT` (10) put the tower top near the
middle of the screen and everything the player had built ran off the bottom —
which reads as the camera sitting too high. On touch-without-keyboard devices the
camera aims lower (`CAMERA_AIM_LIFT_TOUCH`, 1) and stands further back
(`CAMERA_DISTANCE_TOUCH`, 94), which gives the stack back without losing the piece
waiting overhead.

**The playing shot stretches to hold the piece.** `trackingShot` starts from the
frame above — tower top, `aimLift`, `distance` — and then raises its *top* edge to
at least `pieceTop + CAMERA_PIECE_MARGIN`, standing back far enough to fit the
result. A piece always spawns clear of the tower and can be lifted further during
the turn (see [The held piece](#the-held-piece)), so on a tall piece it sits well
above where the old fixed shot's top edge was. The **bottom edge stays put**, so
making room for a high piece shows *more* tower rather than trading it away. With
nothing held (`pieceTop` = 0) this reduces exactly to the fixed shot.

**Width is checked against the real viewport.** Roblox's `FieldOfView` is
*vertical*, so every device frames the same height at a given distance and a phone
held upright sees barely half of what a monitor does across. On those screens the
horizontal axis clips first, and a piece steered to `STEER_LIMIT_X` would slide off
the side. `distanceFor` reads `ViewportSize`, works out the distance that fits
`CAMERA_MIN_HALF_WIDTH` (34 studs — the steering limit plus a piece's half width,
plus air) at the current aspect ratio, and takes whichever of the two axes needs
more room. On a 16:9 monitor the height always wins and nothing changes; on a
portrait phone the camera stands back until the play area fits.

**The checkpoint pull-back** frames the whole leg — `zoneBaseHeight` to `height`,
plus `CAMERA_CHECKPOINT_PADDING` of headroom — through the same `distanceFor`,
with its floor raised to `CAMERA_CHECKPOINT_PULLBACK ×` the normal distance and
the usual `CAMERA_MAX_DISTANCE` ceiling. The floor matters: a short leg already fits in
the ordinary framing, and fitting it isn't enough — the move has to *read* as
stepping back to look at what was built. It eases at `CAMERA_CHECKPOINT_LERP`
rather than tracking at `CAMERA_LERP`.

The server sends no camera cue for any of this. It broadcasts `PHASE.CHECKPOINT`
and this file decides what that looks like, which is what keeps the camera a
deletable presentation (`Presentations.camera = false`).

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

### The round break

The storm landing ends the **round**, and `runRoundBreak` owns everything between
that and the next one. It is the only moment the whole game is stopped:

1. `intermission` goes true and `PHASE.GAMEOVER` goes out. That flag is what makes
   "paused" real rather than cosmetic — the turn queue parks, the height poll
   returns early (which is also what freezes the storm clock), and no piece can be
   held, so **nothing can be placed** for the duration.
2. The wreck flies for `ROUND_BREAK_WRECK_SECONDS` (3). Clients read `GAMEOVER` and
   play `StormFade` — a one-shot white-out that waits
   `STORM_FADE_DELAY_SECONDS` (so the blocks are seen flying *first*), fades to
   white, holds, and clears.
3. **The players vote on how the next round plays** (see
   [the gamemode vote](#the-gamemode-vote)). `startVote` yields here.
4. The winning modifier is applied, the storm clock is set fresh — so no part of
   the new round is spent on the poll — and `ROUND_BREAK_RESUME_SECONDS` later the
   queue starts again.

`TowerService.nuke()` routes through the same function, so buying a Nuke also puts
the next round to a vote.

The camera has its own tell that this is coming: `TowerCameraController` shakes
from `STORM_SHAKE_LEAD_SECONDS` (30) out, ramping on a squared curve so the first
twenty seconds are a faint unease and the tell arrives late. It reads
`stormEndsAt` — the same number the HUD clock draws — so nothing extra goes over
the wire for it, and it stops the instant the storm lands because the server
pushes `stormEndsAt` back out.

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
  normal during early testing, so retro / snowy / stormy / space have not been seen
  end-to-end in a real run. The code paths are short, but they haven't been watched.
  Temporarily zeroing the normal zone's `weight` in `Zones.luau` is the quickest way
  to force one.
- **The new block types haven't been watched in a real run either.** Bomb, Glue,
  Clone, Bouncy, Burning and Noob are all wired end-to-end, but the odds curve is
  deliberately stingy (3% on the first floor), so forcing one means either raising
  `BlockTypes.BASE_CHANCE` or zeroing every other type's `weight`.
- **Name plates disappear on settle**, so there's no way to tell a Glue block from
  an ordinary one once it's part of the tower. That's the intended trade — fifty
  plates is a wall of text — but if a type ever needs to be readable *in* the
  tower, `BlockLabel.dismiss` is the one call to reconsider.
- **Skins are colour and material only.** Making a block actually *look* like a
  Needoh means squash-and-stretch on impact, which is a deformation problem the
  cube geometry doesn't allow. The sound carries it for now.
