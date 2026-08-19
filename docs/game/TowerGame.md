# TowerGame

A Tricky Towers-style co-op stacker. Everyone plays **one shared tower**: players
take turns, each turn hands the holder a tetromino they can slide and rotate, and
a 15-second clock drops it for them if they dither. Over the top of that runs the
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
   [The held piece](#the-held-piece)) and `TURN_SECONDS` (15) on the clock —
   or `IDLE_TURN_SECONDS` (6) until they touch it (see
   [Idle turns](#idle-turns-and-the-inactivity-card)).
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

- Each stage names a `targetHeight` and a clock. The first checkpoint is
  `STORM_FIRST_TARGET` (40 studs) up on a `STORM_SECONDS` (300) clock, and every
  cleared stage puts the next one `STORM_GAP_GROWTH` (5) studs further than the
  last gap — 40, 45, 50 — on a clock `STORM_TIME_GROWTH` (5) seconds longer —
  300, 305, 310.

  **The two grow together on purpose.** A gap that stretches against a fixed
  clock makes every stage strictly harder than the last, so a run ends wherever
  that curve happens to cross the room's throughput; extending the clock
  alongside it means a later stage asks for a *longer climb* rather than a
  faster one.

  **Read the target against the turn budget, not on its own.** A stage is one
  shared allowance of about eighteen turns (the stage clock / (`TURN_SECONDS` +
  `SETTLE_SECONDS`)) however many players are in the room, and a flat piece adds
  `BLOCK_SIZE` (4) studs. The first target used to be 60 — fifteen of those
  eighteen turns spent gaining full height, a three-turn margin for every piece
  that slid off and every player who wasn't looking — and the onboarding funnel
  lost three quarters of its players at the first checkpoint. 40 is ten clean
  placements. The growth is the same 5 the old targets used, so the curve runs
  parallel to the one it replaced, 20 studs below it the whole way up.
- **Cleared** — the tower reaches the target and the [checkpoint cutscene](#the-checkpoint-cutscene)
  runs. Afterwards the floor count is up and the next target is set to *the height
  they actually reached* plus the new gap; overshooting doesn't make the next stage
  free.
- **Expired** — the storm takes everything. See [When the storm lands](#when-the-storm-lands).
- On an empty server the clock is held rather than ticking down to nothing.

A checkpoint floor is stamped out of a **platform layout** — one or more slabs,
possibly with gaps — so it isn't necessarily the single `PLATFORM_SIZE` slab it
used to be, and neither is the base. See [TowerPlatforms.md](TowerPlatforms.md);
with no layouts authored, both fall back to that slab.

Each slab enters with a two-part tween: it stretches out from a sliver at its own
center line while glowing white (Neon), then cools from white to near-black before
dropping back to SmoothPlastic. Because slabs are anchored, tweening `Size` grows
them evenly about their center instead of dragging one face — so a two-slab floor
opens as two slivers spreading apart, and the gap is the last thing to appear.

Checkpoints are tracked in their own list, separate from `blocks` — they have no
physics but still count toward the tower's top.


### The approach: the last minute, as weather

The storm was a number on a bar. `TowerStormController` is the minute before it,
made audible and visible — one ramp, 0 → 1 across `STORM_APPROACH_SECONDS` (60),
driving three things at once:

| | |
| --- | --- |
| **Ambience** | `Assets.Sounds.StormAmbience`, cloned and looped, with **volume *as* the ramp** (`STORM_AMBIENCE_VOLUME` 4x on top of its Studio tuning — a storm arriving over a tower should be the loudest thing in the room by the time it lands). That's what makes "you can't hear it until the last minute" a property of the thing rather than a rule somebody has to keep. It plays from boot at volume 0 rather than starting per approach, because restarting a loop every stage is audible on anything with a recognisable opening. |
| **Clouds** | A `Clouds` instance on `Terrain`, created client-side if the place has none. `Cover` 0.4 → 1, `Density` 0.25 → 1, colour white → slate. Density opens at a quarter rather than three hundredths: below about 0.2 the layer is mathematically present and visually nothing. **If they don't render at all, check `Lighting.Technology`** — Terrain clouds need ShadowMap or Future, and draw nothing under Legacy or Compatibility. The calm end is a *little* cloud rather than none: a sky that grows its first cloud out of nothing reads as a bug, one that thickens reads as weather. |
| **Lightning** | Background strikes, hundreds of studs behind the play plane, **measured from the camera**: `BG_LIGHTNING_ABOVE` / `BG_LIGHTNING_BELOW` are offsets from wherever the eye is, so a bolt is in shot at any altitude and stands 440–1040 studs tall. A fixed band was in frame for the first stage and underfoot for the rest of the run, because the camera climbs with the tower. Each strike gets one clap of the `Lightning` cue, played flat and delayed by `distance / BG_LIGHTNING_SOUND_SPEED` — the lag is what makes a bolt read as far away rather than as an effect that fired late. The gap between them interpolates from `BG_LIGHTNING_CALM_GAP` (7–12s) to `BG_LIGHTNING_STORM_GAP` (0.9–2.6s), so the first bolts are lonely and the last minute is a barrage. Nothing below `BG_LIGHTNING_START_RAMP` (0.12), so the window opens on a clear sky. |

**All of it is presentation.** Nothing here touches the clock, the damage or the
placement rules, and it's all derived from `stormEndsAt` — which every client
already has — so none of it needs a packet. A client that drew none of it plays
the identical game.

**The ramp is chased, not jumped to** (`STORM_APPROACH_SMOOTHING`). Rising, the
window is a minute wide and the smoothing barely shows; the reason it exists is
the fall. The storm lands, the next stage's clock starts, and the target drops
from 1 to 0 on a single frame — a sky that snapped back to clear would undo the
whole effect in the moment it was built for.

**It only runs while a classic run is live.** Three states would otherwise sit at
full storm forever: a PVP match (no storm at all), the round break (the clock has
already expired, so "seconds left" is 0 — which reads exactly like "the storm is
here"), and an idle server. The gate is the phase: `AIMING` or `SETTLING`, and a
positive number on the clock.

### Bolts that branch

`LightningBolt.strike` draws a bolt by **midpoint displacement**: start with a
straight line, split every segment and shove the new middle sideways, halve the
shove, repeat. `BOLT_PASSES` (4) turns two points into sixteen segments that
wander the way a discharge does — the path a spark takes through air is a random
walk, and this is the cheap way to draw one. The shove is rolled about the
segment's own axis, so the wander is 3D: a bolt that only kinked left and right
would read as a paper cut-out from the fixed side-on camera.

Nodes fork with `BOLT_BRANCH_CHANCE` (0.22). A fork is a shorter, thinner bolt
built by the same function at an angle, with one pass fewer — and forks don't
fork, because a fractal that recurses to the leaves is a tree and lightning is a
bolt with a few branches off it. One background strike measures ~56 parts across
a 600-stud drop.

Both kinds of lightning go through it: the storm's background VFX and the Stormy
zone's own strike (`TowerZoneController.drawBolt`), which used to be a single
straight Neon box and read as a beam next to a branching one. The gameplay bolt
takes fewer passes (`LIGHTNING_BOLT_PASSES`, 3) because it lands a few dozen
studs from the camera, where four passes is a scribble rather than a fork, and
its flash lives on its own invisible part — the bolt is dozens of segments now,
and hanging the light on whichever came first would put it at a random height up
the strike.

The parts are anchored, collisionless, unqueryable Neon that fade and delete
themselves, parented to a `TowerStormSky` folder. Nothing reads them back.

## Idle turns and the inactivity card

The stage's turn allowance is the room's, not any one player's, so a player who
isn't there spends the room's budget. They drop the piece from dead centre
whatever the clock says — the last ten seconds of their turn buy nothing and cost
a turn the room needed to make its target.

**A turn opens short and is bought back.** `beginTurn` sets the deadline to
`IDLE_TURN_SECONDS` (6); the first steer or rotate extends it to the stage's full
`turnSeconds`, measured from when the turn started. The test for "touched" is the
same displacement / rotation check that decides whether a turn counts as
`Steered` / `Rotated` for the turn funnel, so there's one definition of engagement
rather than two that can disagree. `turnEndsAt` is a server-time stamp the HUD's
ring counts down from, so the extension replicates as more time on the dial with
nothing to reconcile.

Two exemptions, both in `beginTurn`: a player's first `IDLE_GRACE_TURNS` (1) turns
get the whole clock up front — they're reading the controls hint, and cutting that
short teaches them the game is impatient before they've placed anything — and a
gamemode whose `turnSeconds` is already under the idle window keeps its own, so
the fast mode isn't handed a *longer* turn than it asked for.

**There are two ways to prove you're there, and dropping the piece is the
stronger one.** Steering was the only test at first, and it quietly libelled
everyone who plays by dropping the piece where it spawns — a straight drop down
the middle is a placement, often the right one, and it moves nothing. Two of
those in a row benched a player who was taking every turn. So the turn loop reads
whether `held` went nil on its own (the player's own `Release`) before it drops
the piece itself, and hands that to `noteTurnIdleness` as `autoDropped`: pressing
drop counts however still the piece was. A checkpoint taking the piece mid-turn
also reads as presence, which is the harmless direction — the cost of being wrong
that way is one un-benched idle turn, against a player having to press a button
to keep playing.

**Two untouched turns in a row and they're benched.** `noteTurnIdleness` runs at
the end of every turn. At `IDLE_TURNS_BEFORE_AFK` (2) consecutive untouched turns
it turns the player's **"Not playing"** setting on through `SettingsService.set`
and sends them `Packets.AfkNotice`; the client raises a centred card
(`AfkNotice.ui.luau`) offering **"OK"** (stay out) and **"I'm here!"** (back in).

Some notes on why it's shaped this way:

- **It reuses the existing setting rather than inventing a second kind of
  benched.** The queue already skips spectators (`isSpectating`), the Settings
  window already has the row, and the card's green button is the ordinary
  Settings write — so the two surfaces agree without either knowing about the
  other, and the way back is never a special case.
- **Alone in the server, none of it runs.** `isSpectating` already refuses to
  bench a solo player (the queue would be empty and the game would stop), so
  flipping the setting there would achieve nothing except a card about a rotation
  they aren't in.
- **The card is centred and covers the screen.** A notification in a corner is
  exactly what a player who has wandered off will miss, and it catches the clicks
  that would otherwise reach the HUD behind it.
- **A badge stays up for as long as they're out** (`SpectatorNotice`), whether
  they were benched or chose it in Settings. The card is a *moment* and can be
  missed — dismissed, or arriving while they were looking away, or never sent
  because they joined already spectating — and without the badge the only evidence
  of being out of the game is turns quietly never arriving, which is
  indistinguishable from the game being broken.

  It hangs **centred, under the HUD's top column**, and that placement was
  arrived at by measurement rather than taste. Every corner loses: the turn dial
  sits *outside* the stats column and swings toward the right edge as the screen
  narrows (taking that corner on a phone), while the reaction bar owns a band
  across the vertical middle from x 1459 (taking it on a short window) — two
  hazards that move in opposite directions as the aspect changes, so no fixed
  offset clears both. Left is the rail; bottom-left the controls hint and the
  voice chips; bottom-right the cash counter. Centre-x has no neighbour at any
  size and can only ever overlap the tower — pixels, not buttons.

  It carries a small green **PLAY** button — the same door the card's "I'm here!"
  opens (`TowerAfkController.resume`), worded as a switch rather than an answer
  because the badge is a standing state and not an accusation. Settings is still
  the other route, and the one that can't be covered; see the note on stacking
  below.

  **The badge draws behind the rest of the UI** (`ui.layers.underlay`, ZIndex
  −100), which is why it's its own root — `TowerSpectatorView` — rather than a
  child of the card's. Roots are siblings under one `ZIndexBehavior.Sibling`
  ScreenGui, so a root's own ZIndex is the only thing that decides what covers
  what, and a child can't sit lower than its root however small its number. Two
  stacking answers need two roots. The reasoning is that the badge is a *state*,
  up for as long as the player is out, and the thing it would otherwise cover is
  the HUD they're watching the game through; the card is a *moment with a question
  in it* and stays on top. The trade is that where another root overlaps the
  badge, that root takes the clicks and PLAY is unreachable at those pixels —
  nothing does today, and Settings is the route that can't be.

  `TowerSpectatorView` adds the **GUI inset** back before positioning it,
  converted into canvas units by dividing by the viewport scale. The root ScreenGui sets
  `IgnoreGuiInset`, so canvas y = 0 is the true top of the display and Roblox's
  own topbar occupies the first stretch of it; and because the inset is a fixed
  number of *screen* pixels while everything in the tree is scaled, a plain
  constant is wrong by construction — whatever clears the topbar on a monitor is
  half that on a phone at the 0.5 scale floor. ScaleLayer documents this
  conversion; this is the first thing in the game to need it.
- **Being benched doesn't follow them to tomorrow.** The setting persists — right
  for a player who chose it, a trap for one who stepped away — so the auto-bench
  is recorded as `AutoAfk` in the profile slice and undone on their next join
  (`TowerStatsService.consumeAutoAfk`). Being idle costs a player the rest of that
  session at most.
- The counter resets to zero on the bench as well as on a touch, so a player who
  comes back, takes a turn and wanders off again gets a fresh two turns rather
  than being benched by a single missed one.
- **What closes the card is the transition out of spectating, not the setting
  reading false.** This one is worth remembering, because the level test looks
  identical and is wrong in a way that only shows up on a phone. The bench travels
  over ReplicaService and the card over ByteNet — two transports with no ordering
  between them — and `DataChanged` fires on *any* profile write, cash included,
  which is credited constantly. Test the level, and a payout landing in the window
  before the bench replicates closes the card in the frame it opened. On a desktop
  in Studio that window is nothing; on a phone it was the whole bug, reported as
  "the popup doesn't show".

**The storm blows the tower left.** `breakTower` shoves every block one way —
`STORM_BLAST_HORIZONTAL` (130) negative in X, jittered per block, with a smaller
lift and a little depth — rather than scattering it. A random scatter reads as an
explosion going off underneath, which is already the Bomb's language and the
demolition's; a storm is weather, so it comes from a direction and takes the tower
with it, and the shot ends on an empty arena instead of a cloud of debris.

**Then** the screen goes: `STORM_FADE_DELAY_SECONDS` (1.7) is set to about the
time the wreck needs to clear the frame at that speed, so the order the players
see is the tower leaving and only after that the white-out.
`ROUND_BREAK_WRECK_SECONDS` (3.2) contains both, so no UI opens over the send-off.

**Only the newest platform survives.** When a floor lands, every earlier one goes
out with the scaffolding under it: `blastPlatformsBelow` un-anchors them, turns
off their collision and queries (so a tumbling slab can't shove a surviving block
or swallow the landing preview's raycast on its way past), shoves them with the
same blast the blocks get, and destroys them a second later. A platform is the
ground only until the next one lands above it; after that it's a slab in dead air
that nothing can reach, and leaving the stack standing meant the overview shot
framed the whole dead column instead of the tower being built.

They come out of the `platforms` list *before* they're shoved, for the same
reason `blastBlocks` empties its list first — that list feeds `restingTopY`,
and a slab thrown upward by the blast would otherwise read as the top of the
tower and fire the next piece's spawn into orbit.

The **base is not a platform** and is never demolished: it's where the run
restarts after the storm, and in a Studio-built place it's the user's own tagged
part rather than something the service made. It just ends up permanently out of
frame, since every shot is now measured from the current floor. It's tracked
separately as `baseSlabs` — a list, because a layout base is more than one part —
and the only thing that ever takes it off the board is a PVP match.

The cutoff itself is the bottom of the **lowest slab in the new floor**, not a
fixed thickness below its scoreline: a layout may hang slabs below the scoreline,
and a fixed cutoff would have a floor demolish its own wings on arrival.

Note the asymmetry with the blocks: platforms go by that cutoff, blocks go
regardless of height. The new floor's own slabs are in the `platforms` list, so
the cutoff is what saves them — while a block that survived would be scaffolding
the next stage didn't ask for.

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
4. **The tower is blown apart — all of it.** `blastBlocks(nil)` sweeps every live
   block, not just the ones under the new floor: each is thrown clear with a
   random shove, an upward kick and a tumble, and destroyed
   `CHECKPOINT_BLAST_SECONDS` later. **Nothing carries over into the next stage.**

   It used to sweep by the floor's underside, which spared two things: the last
   layer of blocks (their tops sit inside the slab band, so they stayed, poking
   out around the new ground for the rest of the run) and anything still falling
   above the line. Both are exactly the "previous stage's blocks" a fresh floor is
   supposed to be free of.

   The checkpoint is a clean foundation hanging in the air rather than the cap on
   a growing pile, which is also what keeps a long session from dragging hundreds
   of physics parts behind it. The height readout doesn't flinch: `restingTopY`
   counts checkpoint platforms as well as blocks, so with the tower gone the
   measurement lands on the new platform's own top — which is exactly
   `zoneBaseHeight`.
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

- `Gamemodes.luau` is the content: six modes and, for each, a complete set of
  stage numbers. A modifier is a full set rather than a diff, so there's one
  place to look to know how a round will play and nothing compounds across
  rounds. `DEFAULT` is the un-voted round — what the game did before any of this
  existed, and what a skipped vote falls back to.
- `Gamemode.luau` is the registration hook GamemodeVote auto-discovers. It just
  hands the list over, so nothing in TowerGame requires GamemodeVote to register.
- `settleOnAMode` is the shared half: it calls `GamemodeVoteService.startVote()`
  (which **yields** for the length of the poll), feeds the winner to `applyStage`,
  and keeps going while the winner is PVP — so a PVP vote plays a match and then
  asks again rather than dropping the room into a classic run nobody picked.
- Two callers use it, and everything that happens *once* per round stays outside
  it: `runRoundBreak` (after a storm) and `runOpeningVote` (once at server start).

| Mode | What the next round does |
| ---- | ------------------------ |
| Classic | Nothing. The un-voted numbers, exactly. |
| Tower Rush | Two thirds of the usual storm clock for the same target. |
| Blitz Builder | Half the turn clock. The storm clock is left alone, so shorter turns buy the players *more* attempts, not fewer. |
| Roulette | **70%** of pieces are special — a flat `blockTypeChance` that bypasses the curve *and* `MAX_CHANCE`. |
| Lightning Storm | Lightning strikes in **every** zone, not just Stormy. |
| Wild Weather | **Only special zones.** The calm zone is out of the game: the round opens in a special and every checkpoint rolls another one (`specialsOnly` → `Zones.rollSpecial`). |
| PVP | **Replaces the round.** Six lanes, no turns, tallest tower before the clock — see [TowerGamePvp.md](TowerGamePvp.md). |

**PVP is the one mode that isn't a set of numbers.** Its modifier carries
`pvp = true`, and `runRoundBreak` reads that as "hand the board to `PvpService`
and wait", then puts the ballot back up rather than starting a classic run
nobody picked. Everything else in this document describes the classic round; the
PVP round shares this file's *block engine* (pieces, physics, hazards, the play
plane) and none of its turn queue, storm or checkpoints.

**The ballot is four panels: two permanent, two rolled.** Classic (`order = 0`)
and PVP (`order = 1`) both carry `pinned = true`, so they're always the left-hand
pair and the two rolled twists are always the right-hand pair — a player who wants
either of the game's two real ways to play learns one place to look instead of
reading the ballot every round. PVP is pinned because it's a mode players ask for
by name, and at two rolled slots against five twists the roll would have offered it
on about two ballots in five. Classic is pinned for the older reason: a ballot of
nothing but twists gives the players no way to decline one, and Classic is that
answer — the one panel you can pick without reading. Its modifier *is*
`Gamemodes.DEFAULT` — winning Classic
and skipping the vote have to produce the same round, or one of them is lying.

Registering another mode makes the ballot more varied, not wider: the two rolled
panels are drawn from every unpinned mode, so a new twist lengthens the pool and
nothing else.

**The winner holds for the whole round**, across as many checkpoints as the
players clear. `runCheckpoint` deliberately doesn't re-vote: changing the rules
out from under a run in progress is what this placement avoids.

The moment is chosen for what's already true: the round is over, the tower is
wreckage, the queue is parked and the storm clock is frozen (`intermission`), so
the vote has the board to itself and needs no state of its own to get it.

**Both clocks ride in the `State` packet.** The HUD draws them as fractions — the
turn ring against the turn length, the storm bar against the stage length — so a
client reading them off `Constants` would draw the wrong shape for every voted
stage. `applyStage` is the one place that writes `stage`, and it mirrors
`turnSeconds` into `state`; `stormSeconds` is left to `restartStormClock`, since
the stage length isn't the gamemode's number alone — it's that plus
`STORM_TIME_GROWTH` per floor already cleared. Both clocks are therefore always
written before the broadcast that follows.

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
- **It doesn't reach anything that isn't a part.** Two things on a piece are drawn
  from geometry rather than as geometry, and both have to be `Enabled = false`d by
  hand alongside the hide: the **name plate** (a GUI) and the **type tell** (a
  `Highlight`). The plate was handled from the start; the tell was not, so the
  holder steered a preview wearing its own tell while a second copy hung a frame
  behind it at the server's position. Two offset outlines of the same block, which
  reads as the block wearing a crooked clone of itself — obvious on a loud tell
  like the Bomb's, near-invisible on a quiet one, which is why it looked like a
  per-type bug rather than a per-piece one. Only the holder's view is touched;
  everyone else is watching the real piece and should see its tell all the way
  down.

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

## What a block is made of

A piece is **four welded 4×4×4 cubes wearing one rounded shell**, and the split
between those two things is the thing to hold on to.

The cubes are the game: they collide, they carry the mass, and every measurement
in `TowerService` lands on them. They are square on purpose — a rounded collision
shape settles into its neighbours' corners, and a flat course would stop being
flat. They are also **invisible**.

What you see is the **body** (`BlockBody.luau`): a single CSG union of the whole
tetromino with its corners rounded, one per shape, out of
`ReplicatedStorage.Assets.BlockBodies`. The rounding runs *through* the joints
between cells — a cell with a neighbour drops its rounding on that side and the
edge cylinders are stretched across — so a piece reads as one moulded shape
rather than four blocks bolted together. Rounded only at the shape's true outside
corners.

**Each client builds its own** (`TowerBodyController`), and that is not an
optimisation, it's the only way it renders. The body was server-made and welded
on first. It replicated with the right `Size`, the right `TriangleCount` and its
mesh present — every measurement came back clean — and drew on the client as a
tiny cube. A union the client clones out of its own ReplicatedStorage draws
correctly, which is what the aim preview had been demonstrating the whole time:
the preview looked right while the dropped block didn't, because the preview is a
clone the client made.

So the server ships four **visible** cubes and stamps the shape id on the model;
each client clones the matching body, hides the cubes with
`LocalTransparencyModifier`, and drives the body off the root cell every frame.
Nothing extra crosses the wire, and the server view stays readable for debugging.

The body is `CanCollide` false, `CanQuery` false, `Massless` and never welded —
welding a local part onto a server-owned assembly puts a render instance into the
physics engine's idea of that assembly. That is what makes it safe to **resize**,
which is how the squash works: a damped spring off each impact writes the body's
`Size` and offsets its CFrame so the compression happens *onto* the surface it hit
rather than about its own centre. Doing any of that to a cell would change its
mass (breaking the Anvil and Feather densities), change its collision, and corrupt
`partTopY` → `restingTopY` → `SPAWN_CLEARANCE`, which is how a piece ends up
spawning inside the tower.

Three consequences worth knowing:

- **The server never mentions the body, and `modelParts` is unchanged.** Nothing
  in the simulation has to know bodies exist, because on that side they don't.
- **The body mirrors its cells.** Colour, material and transparency are read off
  the root cell every frame, so every server-side effect reaches the screen
  without knowing about bodies: a bomb's red flash, a burning block charring and
  fading, a ghost going see-through, a zone re-dressing the tower.
- **The Retro zone takes the coat off.** Studs are a property of a flat face and
  render as nothing on a rounded one, so when the client sees studs on a cell it
  hides the body and shows the square cells — which is what a 1962 brick should
  look like. Read off the cells, so it needs no packet and no state.
- **A missing asset degrades to the old game.** No `BlockBodies` folder, or a
  client that can't build one, means the visible cubes are the block and the game
  looks exactly as it did before bodies existed.

Skins still own **material and colour**, so a Concrete block is a rounded concrete
block and Needoh is rounded glass. The shape is the house style; the surface is
still the thing being sold.

The body **mirrors the cells**, which is how every server-side effect reaches the
screen without knowing bodies exist. Colour, material and transparency are
assigned every frame in `step`; a skin's `Texture` children are cloned onto the
body once at attach instead, because unlike the other three nothing in the game
re-textures a block after it's built. A texture that only lived on a cell would
be a pattern nobody ever sees — the cells are hidden behind the body.

## Blocks: skins and types

Every piece rolls two independent things at spawn.

Colour is **not** one of them: every piece rolls its own random hue at a fixed
saturation and value, so blocks are vivid and varied without any coming out
muddy. Shape is read from silhouette, not colour.

**Skins** (`BlockSkins.luau`) are pure flavour — a surface and the sounds it
makes. They come from the ASMR kit in the place, so the asset ids there
are ones that kit actually ships; don't invent new ones without checking they
resolve, or a skin goes silent.

Surface is `material`, plus an optional tiled `texture` over it — Duck is the
only skin that uses one. A `Texture` rather than a bespoke material so the hue
roll underneath still shows and every effect that repaints a block (a bomb's red
flash, a burn charring it) keeps working with nothing written for it.

| Skin | Look | Lands like | `squish` | weight |
| ---- | ---- | ---------- | -------- | ------ |
| Classic | Concrete, grey | Needoh's squish folder, at the same 0.7 volume | 0.15 | 4 |
| Needoh | Glass, pink | squish, plus a release beat as it settles | 1.0 | 3 |
| Butter | SmoothPlastic, yellow | Needoh's squish folder, same settle beat | 0.75 | 3 |
| Wood | WoodPlanks, brown | a hard thunk | 0.12 | 1 |
| Grass | Grass, green | a muted thud, with a settle beat | 0.45 | 1 |
| Concrete | Concrete, grey | the same knock pitched down heavier | 0.06 | 1 |
| Duck | SmoothPlastic, yellow, **tiled duck texture** | a quack | 0.8 | **0** |

**Duck never rolls.** Weight 0 can't be reached by the walk in
`BlockSkins.random`, which is the point — the only route to it is the
`skins.duck` pack, and that pack is only ever granted (see
[The Duck skin](#the-duck-skin)). It stays in `List` because `get`, the cmdr
`skin` command and the shop card's preview all look skins up there.

The rare tier below is Wood, Grass and Concrete — Duck isn't part of the roll at
all, so it isn't part of the rarity conversation either.

Those three are a deliberate **rare tier** — one weight each against the stock
three's 3-4, so each turns up about a third as often as Butter and all three
together are under a quarter of pieces. They hold the ends of the squish scale
(0.06 and 0.45) rather than its middle, and a tower built mostly out of the
extremes stops reading as a range.

**Classic, Needoh, Butter, Wood and Grass each play from a folder of takes**, not
from one sample: `impactFolder` names a folder under `Assets.Sounds.Impacts`
(`Needoh` — 7 squishes, shared by Classic, Needoh *and* Butter, `Wood` — 5 panel
thunks, `Grass` — 6 footsteps, wet and dry mixed) and
`BlockSkins.impactIdFor` rolls one **per landing**. Pitch randomisation alone
wasn't enough at this repetition rate: the ear catches a repeated *sample* long
before it catches a repeated pitch, and a tower is forty landings of the same
material.

Their `impactSound` ids stay as the fallback for a place without the folder
(Rojo doesn't sync it), which is also what **Concrete** still runs on — a
placeholder that resolves because it's already in `Assets.Sounds`
(`NormalBlockCollision`, pitched down), picked so a skin is never silent. Giving
it a folder is a one-line edit plus a folder of Sounds.

Note that **Concrete and Classic share a material** — though no longer a sound,
now that Classic lands on the squish folder and Concrete is the last skin holding
that knock. Classic *is* the concrete block; the rare one is heavier and duller
and exists to sit at the bottom of the squish scale. If the pair reads as one skin in play, the fix is to re-material
Classic (Plastic, say) rather than to add a third grey.

`squish` is how far the skin deforms on impact, 0 = rigid, 1 = full jelly. It's
read by `TowerJellyController` — **temporary dev scaffolding**, one client-side
file that squashes a `SpecialMesh` on every block with a damped spring. Delete
that file and `squish` becomes an unread number; nothing else consumes it. The
skin id reaches the client on the `SKIN_ATTRIBUTE` the server stamps in both
`buildPiece` and `registerBlock` — both, because a piece is parented into the
arena as the *held* piece and doesn't reach `registerBlock` until it's released,
so stamping only there left the client reading a default for the whole fall.

Id 4 is **retired**: it was "Glow", a Neon skin that rolled for free. Neon is a
purchase now (see [Skin packs](#skin-packs)), and a stock skin that already
glowed would have made the thing being sold look like nothing. Ids go over the
wire — append, don't renumber.

Skins change **surface and color only, never geometry**. The kit's meshes are
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
| **Bomb** | Explodes. | Beeps and flashes red three times on impact, then detonates and consumes itself. `EXPLOSION_RADIUS` 36, impulse 95 — a hole in the tower, not the end of the run. |
| **Glue** | Glues parts together. | Welds to everything it's resting against, on settle. Every *block* it caught wears a faint green Highlight for the rest of the run — the base and the platforms don't, because they aren't blocks. |
| **Clone** | Duplicates itself. | Drops a copy of itself in from `CLONE_RISE` above, on settle — same shape, skin, pack and colour, minus the type. |
| **Bouncy** | Bounces! | Lands with `BOUNCY_PHYSICS` instead of the dead default. |
| **Burning** | Burns blocks, careful! | Arrives alight; chars black over `BURN_SECONDS` (20) and disintegrates, spreading to whatever it touches — up to `BURN_MAX_SPREAD` (3) other blocks per fire. |
| **Noob** | Places a Noob. | Replaces the tetromino with a Noob that walks and jumps until something lands on it. |
| **Anvil** | Heavy! | Ten times the density (`ANVIL_PHYSICS`). Ploughs through what it lands on, immovable afterwards. Draws speed lines on the way down and lands on its own `Anvil` cue instead of the skin's impact sample. |
| **Ice** | Nothing sticks. | `ICE_PHYSICS` — friction taken out, high `frictionWeight` kept so the ice wins the contact and things slide *on* it. |
| **Anchor** | Locks itself in place. | Anchors every one of its parts on settle, and turns to stone doing it. Holds itself, welds nothing. |
| **Mystery** | ??? | Lands as a question mark, then rolls one of the landing types and fires it. |
| **Crate** | Breaks apart! | **Benched** (`disabled = true`). Cuts its own welds on settle and collapses into the loose cubes it was pretending to be. |
| **Feather** | Takes its time. | Terminal velocity of `FEATHER_FALL_SPEED` (12 studs/s) on the way down, and light enough to shove nothing. |
| **Ghost** | Falls through the tower. | Phases through every block for `GHOST_SECONDS` (1.2) after release, then turns solid wherever it got to. Still lands on the base and the platforms. |
| **Magnet** | Pulls blocks in. | On settle, holds a pull field for `MAGNET_SECONDS` (0.55): everything within `MAGNET_RADIUS` (36) is dragged toward it at `MAGNET_ACCEL`, falling off with distance. |
| **Sacrifice** | Destroys the block it hits. | On contact, unmakes the block it ran into — which glows, drifts off and fades — and carries on into the hole. Hitting only the base, a platform or air means the sacrifice is spent for nothing. |
| **Lightning** | Calls down a strike. | On settle, drops the Stormy zone's own bolt on its own position — same flash, same sound, same `LIGHTNING_RADIUS` (26) blast — and is consumed by it. No warning marker. |

Details worth knowing:

- **Glue leaves a mark.** It's the one effect whose result is otherwise invisible:
  the welds are real and permanent, and the only way to find out which blocks were
  caught was to knock the tower and see what refused to move. Each glued block now
  wears a second, fainter Highlight (`GlueTell`) in the Glue type's own tell
  green, so the piece that did it and the blocks it did it to read as one cluster.
  Only blocks are marked — the base and the checkpoint platforms get welded too,
  and `blockByModel` is what tells them apart, so "is it a block" and "is it not
  the floor" are one question. Idempotent: a block glued twice wears one mark.

- **Anvil is felt on the way down.** Its density is the mechanic, but density is
  invisible until something gets crushed, so both halves of the tell are about the
  fall: one narrow `Trail` per cell (`ANVIL_LINE_*`), and its own landing sound
  (`BlockTypes.impactCue` → the `Anvil` cue), played *instead of* the skin's
  sample — two impacts on one frame read as a stutter, not as weight. The trails
  are attached at release rather than at build, or a piece being steered around
  the sky for a turn would draw speed lines while the player was still deciding. A
  Trail needs no velocity gate: it only draws while it's moving.

- **Anchor turns the block to stone** (`petrify`): grey `Color` and a Slate
  `Material` on every cell, skin textures hidden, and a `Statue` attribute that
  makes `applyZoneLook` skip it — the same carve-out a Noob gets, and for the same
  reason. Without it the next zone change would hand the statue its skin back.
  Colour *and* material because the client's rounded body mirrors exactly those
  two properties off the cell, so that pair is what actually turns the shell a
  player sees into stone. A block that can never move again has stopped being part
  of the tower and started being scenery; this is it looking like it.

- **Lightning** — the storm's hazard, handed to a player, through the same
  `strikeLightning` the storm's own clock calls. What changed to allow that: the
  function no longer clears `WARN_ATTRIBUTE` (the marker belongs to the storm's
  state machine, which now clears it beside its own `pendingStrikeX = nil`, so a
  Lightning block landing mid-warning can't wipe the marker for a strike that is
  still coming), and it takes an `exclude` so the block that called the bolt isn't
  thrown before being destroyed.

  Read it against **Bomb**, which is the type it shares a job with. A Bomb is the
  bigger hole — radius 36 against 26, impulse 95 against 43 — and announces itself
  with three beeps, so the room watches the damage coming. A strike is over before
  anyone looks up. Smaller bite, no notice; that trade is the whole type.

  It needs no lane check in PVP: radius 26 against `LANE_SPACING` 120 leaves the
  nearest neighbouring tower ~94 studs outside anything `blastAt` touches. And the
  client draws the bolt off `STRIKE_ATTRIBUTE` ungated by mode or zone, so it
  renders in a match even though the *zone* hazard is switched off there.

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
  its own parent. The copy carries no **type** — a clone that cloned would bury the
  arena inside two turns — but it does carry everything else, and the colour is the
  part that had to be fixed. `buildPiece` rolls a fresh hue per block, so a Clone
  used to hand back a piece in an unrelated colour: the one type whose whole
  promise is that what it makes looks like what it came from, and the only one that
  visibly broke it. It now takes an optional `color`, and Clone is the only caller
  that passes one — `block.baseColor`, not the current cell colour, so cloning a
  charring Burning block or a Bomb mid-flash copies the block rather than the state
  it happens to be in.

  It went unnoticed because a player wearing a **colour pack** never saw it:
  `SkinPacks.colorFor` returns the same shade for both, so the copy matched by
  accident.
- **Burning** is a *state*, not just a type. `igniteBlock` can be called on any
  block, and it is: `spreadBurn` runs from the height poll (not from `Touched`,
  because a block already resting against its neighbour never fires `Touched`
  again) and lights anything within `BURN_SPREAD_RADIUS`, after a
  `BURN_SPREAD_DELAY` grace so a burning piece doesn't take the whole course it
  landed in with it. A lit block lerps from its own colour to black and fades out
  over the last `BURN_FADE_FRACTION` of its life. The hazard isn't the block, it's
  the hole it leaves.

  **A fire takes at most `BURN_MAX_SPREAD` (3) other blocks.** The budget belongs
  to the *fire* — every block lit from the same original shares one counter, held
  by reference on `block.fire` — rather than to each block, because three
  neighbours each would be a tower alight by the third hop. It's spent in
  `spreadBurn`, one per newly-lit block, so a fire that spreads as a line and one
  that spreads as a fan both cost three. The piece that arrived alight isn't
  counted: it was always going to burn, and what the cap bounds is the damage done
  to what was already built. Two Burning pieces are two fires with a budget each —
  they're two hazards.

  Uncapped, a Burning piece dropped into a well-packed tower ate as far as blocks
  were touching, which on a good stack is all of them — so the tower the room had
  built most carefully was the one it punished hardest. The check mirrors
  `igniteBlock`'s own three refusals (already alight, custom rig, destroyed) so
  the budget is never charged for an ignition that didn't happen; a fourth refusal
  added there needs one here too.
- **Noob** is the one type that **overrides the model** (`overridesModel` in the
  type table). Instead of tetromino cells the holder aims a Noob rig, and once it
  settles it stops being cargo: `NoobBlock.activate` walks it randomly along X
  (never Z — the plane clamp would fight it) and jumps it at `NOOB_JUMP_CHANCE`.
  Any block landing on it at speed kills it, and it ragdolls and despawns. It's
  excluded from the height, from the zone dressing, and from the plane clamp's
  angular term (it has to be allowed to turn around to face where it's walking).
  The rig is a **Studio asset**; a missing one silently rolls an ordinary block
  instead, so a Noob costs you the joke rather than the turn.

- **Anchor** is the one type that is straightforwardly *good news*, and it cuts
  both ways: it freezes where it stopped, so a lucky placement becomes permanent
  scaffolding and a bad one becomes permanent clutter. It anchors **itself**, not
  its neighbours — a bomb can still clear the blocks around it, leaving a ledge
  hanging in the air. `unanchorModel` is what stops it surviving a demolition:
  neither the checkpoint blast nor the storm is something a block gets to opt out
  of.
- **Crate** is **benched** — `disabled = true` in `BlockTypes`, so it is never
  dealt and never revealed by a Mystery. It stays in `List` and in `byId` on
  purpose: an id that has already gone over the wire has to keep resolving, and
  `block Crate` still forces one for testing. Delete the one line to put it back.
  Everything below still describes what it does when you do.
- Crate breaks on **settle**, like Glue and Clone, and for the same reason —
  a crate that came apart the instant it grazed something would scatter on the way
  down and read as the piece failing to exist. Landing first and *then* falling
  apart is one beat the room can watch. The cells stay inside one model and one
  `Block` entry (same tower mass, destroyed together by the demolition), and the
  `shattered` flag is what tells the plane clamp to hold each cell to the plane
  separately now that they're no longer one welded assembly. A one-cell piece has
  no welds and is left alone.
- **Feather** is a **velocity clamp**, not a density. Gravity is an acceleration,
  so a light block falls at exactly the same speed as a heavy one — the drift is
  `FEATHER_FALL_SPEED` capping downward velocity in the plane poll, folded into
  the write that clamp was already making. Only the downward half is capped, so a
  blast can still throw one. It buys the holder several extra seconds of steering
  at the cost of the same seconds off their turn clock. Every *other* block is
  capped in the same line at `FALL_SPEED` — see [Landing feel](#landing-feel).
- **Ghost** is the only type that acts during the **fall** rather than at either
  end of it, and the only one that needed a new mechanism: **collision groups**.
  Every block goes in `BLOCK_COLLISION_GROUP` at `registerBlock`; the base and the
  checkpoint platforms stay in `Default`; a ghost sits in `GHOST_COLLISION_GROUP`,
  which is set non-collidable with the first and left collidable with the second.
  That distinction is the whole design — "passes through everything" would mean
  falling out of the world, which is a lost turn rather than a clever one.
  Transparency is saved per part and restored, because skins set their own (Needoh
  is translucent) and blanket-restoring to 0 would repaint a skin someone bought.
  Solidifying *inside* another block is a real outcome and deliberately not
  guarded against: the physics shoves the two apart and the tower lurches. Aim
  well and it's the best piece in the game; aim badly and you've wedged your own
  tower.
- **Magnet** is a **field**, not a blast with the sign flipped — and getting there
  took three tunings, which is the part worth keeping.

  The first two (`22/26`, then `30/60`) were a single `ApplyImpulse` on settle, and
  both were invisible in play. Raising the number was the wrong lever twice,
  because the number was never the problem. An impulse is *one* change in velocity
  and static friction erases it in about a fifth of a second — at half radius the
  first numbers bought a third of a cell of travel, and nothing at all for a block
  boxed in by its neighbours. Worse, a Magnet lands on a tower that has been
  sitting still for a minute, and **a settled Roblox assembly is asleep**; an
  impulse into a sleeping assembly is not something to rely on.

  So `pullTick` writes `AssemblyLinearVelocity` (which is what reliably wakes an
  assembly) and re-applies an acceleration **every frame for `MAGNET_SECONDS`**.
  Friction has to be beaten continuously instead of once, which is the difference
  between a number on paper and a tower visibly leaning in. Velocity is
  accumulated rather than set, so a block already moving is steered rather than
  stopped and the field builds over its window instead of teleporting anything on
  the first frame. The origin is re-read each frame, so a magnet that gets shoved
  mid-pull drags its field with it.

  `MAGNET_LIFT` (0.2, against a blast's 0.6) angles a little of the tug upward to
  unstick a resting block instead of grinding it into the floor it sits on. The
  earlier argument against any lift — that it would hand the room free height for
  landing one piece — doesn't survive the tug being *inward*: what a lifted block
  does next is come down closer in. A pull is self-limiting for the same reason,
  since everything it moves is moving into the block that pulled it. Anchored
  blocks are skipped outright rather than left to ignore the write, so a Magnet
  can't drag the floor out from under anyone.
- **Sacrifice** is the one type whose effect is a **trade** rather than a hazard.
  Every other special piece is something to survive; this is a tool, and the tower
  it's aimed at is usually your own — you spend a turn and a block you already
  built to unmake a placement the room regrets. Landing it on a badly wedged
  **Anchor** is the best thing it does, and the reason anchored blocks aren't
  spared: a bomb can already clear one, so "locks itself in place" was never a
  promise against demolition.

  It resolves on **contact**, in `watchLanding`, and that's what makes it a piece
  you *aim*: the block it takes is the one it hit. Steer it into the side of a
  stack and it takes the block it ran into, rather than whatever it happens to be
  resting against once it has tumbled to a stop. It's tested ahead of the
  impact-speed gate the Bomb sits behind, because "you hit the block you were
  aiming at, but too gently for it to count" is a rule nobody can see. Anything
  that isn't a live block — the base, a checkpoint platform, the wall — isn't in
  `blockByModel` and is safe by construction; hitting one of those leaves the piece
  still armed for the block it was actually aimed at, and hitting nothing at all
  simply spends it. It fires once (`resolved` is latched before the effect runs),
  so a Sacrifice that drops through its own hole and clips something on the way
  doesn't eat the tower a floor at a time.

  **The block that goes gets a send-off.** It's destroyed on the frame it's hit —
  collision, height, welds and all — and what glows, drifts up and away, and fades
  out over `SACRIFICE_FADE_SECONDS` (1.1) is a *copy* parented into the arena as
  `SacrificedBlock`: anchored, `CanCollide`/`CanQuery`/`CanTouch` off, moved by
  hand from its own pivot. Cloning is what keeps the two halves honest — the
  removal stays the plain `Destroy` it always was, so nothing can collide with a
  corpse, count it as height, or be dragged along by a glue weld that outlived its
  block, while the animation is free to take a second over it. The corpse needs no
  client code: it carries the shape attribute, so each client bodies it like any
  block and drives that body from the cells' colour, material and transparency —
  the same route a burning block chars by. A **Noob** is taken without the
  send-off; a rag-doll rig drifting up the screen is a different effect than the
  one this is.

  On the one path that has no impact to read — a **Mystery** revealed as a
  Sacrifice, which has already landed — it falls back to what it's standing on.
  `blockUnder` casts one ray per cell from the cell's own **centre** downward,
  starting at the centre rather than the bottom face because a ray that begins
  exactly on a surface is free to miss it, and the surface in question is the one
  it's touching. Nearest hit wins, so a piece bridging two towers takes the one
  it's actually on, and `SACRIFICE_REACH` (1.5) is short so a piece spanning a gap
  can't reach *through* it for a block it never touched.
- **Mystery** is a bluff: you place it exactly as carefully as you'd place the
  worst thing it could be. It rolls from the types flagged `viaMystery` — Bomb,
  Glue, Clone, Burning, Anchor, Magnet, and Crate once it's off the bench —
  weighted by the same `weight` the ordinary
  roll uses, so a type that's rare as a piece stays rare as a reveal. A `disabled`
  type is out of this pool as well as out of the deal, so benching one can't reach
  players through the back door of a reveal. The physics
  types are deliberately excluded: an Anvil reveal would be a word with no event
  behind it, since the block has already fallen at ordinary weight. The reveal
  re-tints the `Highlight` and puts a **fresh name plate** up for
  `MYSTERY_REVEAL_SECONDS`, because the original was dismissed on settle a moment
  earlier. Bomb is reachable only this way at settle time — a block *dealt* as a
  Bomb arms on impact instead.

A special block is marked with a `Highlight` in its type's color rather than by
repainting it — the skin already owns the color.

Bouncy, Anvil, Ice and Feather own their own `CustomPhysicalProperties`, resolved
through the `TYPE_PHYSICS` table `basePhysics` reads — adding another physics type
is a line in that table, not a branch. `applyZoneLook` is what keeps them from
being clobbered when a zone re-dresses the tower, with one carve-out: Snowy wins
on **friction and elasticity** (a slippery zone is the whole point of it) but
**density survives the weather**, because density isn't a surface. Without that,
an Anvil would stop being heavy the moment it started snowing, which reads as the
type having broken rather than as the weather.

**The ground is not a block, and uses `FLOOR_PHYSICS`.** Roblox blends a contact
as `(v1 * w1 + v2 * w2) / (w1 + w2)`, so a weight is a claim about which of the
two surfaces decides. Bouncy's `elasticityWeight` of 10 and Ice's `frictionWeight`
of 10 exist to win that claim against the dead, inelastic blocks they land on —
which is the mechanic. They used to win it against the *floor* too, because the
base, the checkpoint platforms and the PVP lane platforms all shared
`BLOCK_PHYSICS`:

| Contact | Was | Now |
| ------- | --- | --- |
| Bouncy on the floor | 0.65 elasticity | **0.07** — dead, as ground should be |
| Ice on the floor | 0.46 friction | **0.82** — grips, as ground should |
| Bouncy on a block | 0.65 elasticity | 0.65 — unchanged |
| A block on the Ice | 0.46 friction | 0.46 — unchanged |
| Anything else on the floor | 0.90 friction | 0.90 — unchanged |

**Every floor wears it, however it got here.** Five paths produce ground - a
tagged Studio part, an authored base layout, the generated base, checkpoint slabs,
and PVP lane platforms - and for a long time only the ones that *built* a part set
its physics. The two that **adopt** one did not, so a Studio-authored base kept
stock plastic physics (friction 0.3, **elasticity 0.5**) and was therefore bouncy
and slippery: blocks landed on it, bounced, and slid off. Checkpoint slabs escaped
it because `playInSlab` sets the properties again a moment later; the base has no
such second pass, which is why the symptom was the baseplate and nothing else.

`PlatformLayouts.build` now sets it on every slab it stamps out, and `buildBase`
sets it (and `Anchored`) on a tagged part it adopts - the same argument the
`Anchored` line there was already making, applied to the other property a floor
cannot afford to be wrong about.

`FLOOR_PHYSICS` is `BLOCK_PHYSICS` with both weights pinned at 100, so the floor
decides its own contacts and a type's weight is only ever pitted against blocks.
Every mechanic survives: Bouncy still bounces off towers, Ice is still slippery to
build *on*. Only the ground stopped playing along.

It surfaced in PVP, and that's not a coincidence — a lane starts empty and stays
short, so a large share of a match's pieces land on bare platform rather than on a
tower. Classic hid the same bug behind one tall shared tower.

Note that adding six types roughly halved how often each *individual* type comes
up — the overall odds that a piece is special are unchanged (that's the curve
above), but the pool it rolls from is now twice as deep.

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
  out of `LocalTransparencyModifier`'s reach). The **type tell** is disabled on the
  same line and for the same reason — see [Aiming](#aiming).

Three edge cases the input controller handles, all of which come from "held" being
a state rather than an event:

- **Two keys at once** — releasing one resumes the other, rather than stopping dead.
- **Lost key-up** (alt-tab mid-glide, gamepad unplugged) — `WindowFocusReleased`
  force-releases, otherwise the piece would slide to the travel limit.
- **Already holding when the turn starts** — no input event fires for a key that
  never moved, and the server clears the steer direction on every new turn, so the
  controller re-asserts what's held when the piece becomes ours.

Touch steers with a **drag**, not taps: `SteerStick` reports a continuous
`[-1, 1]` into the same analog `setSteer` the gamepad uses, so holding a
deflection keeps the piece moving. It self-centres — releasing reports `0`
exactly once, because a stick that stayed where you left it would keep the piece
sliding after your thumb was gone. The control is also cleared when it's
disabled, since it's greyed out between turns rather than unmounted.

(This replaced a pair of LEFT / RIGHT buttons that each sent a fixed pulse. They
couldn't express *how far* to move, so every placement was a burst of taps.)

The stick is **composed from the shared kit**, not drawn: the track is `ui.Panel`'s
dark-glass surface and the knob is `ui.Panel` in gem mode (`STICK_KNOB_VARIANT`,
blue — TURN is purple and DROP is red), so it picks up the active skin like every
other primitive. `STICK_TRACK_HEIGHT` matches the button height beside it and the
knob is sized from it at render (`theme.padding + theme.strokeThickness` in from
each edge), so a live theme edit in UI Labs re-fits the control.

## Stats and saving

`Blocks Placed` and `Biggest Height` show on the in-game leaderboard and persist
across sessions.

- `PlayerData.luau` registers the `TowerGame` profile slice through the standard
  discovery convention — PlayerData never mentions this feature.
- `TowerStatsService` owns the reads and writes and mirrors them into a
  `leaderstats` folder. The profile is the truth; the leaderstats values are
  display mirrors (the height column is floored to an integer, the profile keeps
  the decimals).
- The slice also carries `SeenCheckpoint`, which is **not** a stat — it's a
  write-once false → true flag saying whether this player has ever been in the
  server when a checkpoint cleared. It's what qualifies them for the
  [first-checkpoint quest](#the-first-checkpoint-quest), read through
  `isFirstCheckpointFor` on the server and off the replica by the HUD. It's on
  the profile rather than in a session variable so a player who leaves during
  their first run doesn't come back and get handed the same prize twice.
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
That includes `ServerStorage.TowerPlatformLayouts`: with no layouts authored, the
base and every checkpoint are the plain `PLATFORM_SIZE` slab. See
[TowerPlatforms.md](TowerPlatforms.md).

### Where the arena sits — building a map around it

The arena is fixed in world space, so a background map can be built against
these coordinates. **+Z is the front**: the camera always stands on the +Z side
at `x = 0` and looks down −Z at the play plane (`CFrame.lookAt` in
`TowerCameraController`), so scenery belongs at −Z and the corridor in front of
the tower has to stay empty.

| What | Where | From |
| ---- | ----- | ---- |
| Play plane | `z = 0`; blocks are 4 deep, so they occupy `z −2 … +2` | `PLANE_Z`, `BLOCK_DEPTH` |
| Base platform | 48 × 4 × 8 centred at **(0, 40, 0)** — top surface **y = 42** | `PLATFORM_SIZE`, `BASE_POSITION` |
| Build column | `x −24 … +24` (pieces steer to ±22 and overhang) | `STEER_LIMIT_X` |
| First checkpoint floor | **y 82 – 86** (40 studs above the base top) | `STORM_FIRST_TARGET` |
| Later checkpoints | +45, +50, +55 … above the last one; everything below each new floor is demolished | `STORM_GAP_GROWTH` |
| Camera, desktop | (0, ≈66, **+78**), FOV 60 vertical | `CAMERA_DISTANCE` |
| Camera, phone | (0, ≈57, **+94**) | `CAMERA_DISTANCE_TOUCH` |
| Camera, max pullback | up to **z +420** on overview / checkpoint shots | `CAMERA_MAX_DISTANCE` |
| On screen at round start | ≈160 wide × 90 tall at the play plane (16:9) | FOV × `CAMERA_DISTANCE` |

Two consequences for scenery: **nothing may sit between `z = +6` and `z = +420`
near `x = 0`**, or a wide shot will frame it instead of the tower; and the tower
climbs without limit inside one stage, so anything meant to stay in frame either
repeats vertically or lives far enough out to read as a skybox.

### Assets to create

All under `ReplicatedStorage.Assets` (Rojo does **not** sync these).

| Asset | What it is | Missing means |
| ----- | ---------- | ------------- |
| `Assets.Noob` | A `Model` with a `Humanoid` and a `HumanoidRootPart` — a classic Noob rig | The Noob type silently rolls an ordinary block instead |
| `Assets.BlockBodies` | Seven CSG unions named `I` `O` `T` `S` `Z` `J` `L` — the rounded shell each shape is seen as. **Don't hand-build these**: paste `tools/build-block-bodies.luau` into the command bar in Edit mode, which also stamps the `CellOffset` and `BaseSize` attributes the runtime reads | Blocks render as the plain visible cubes they used to be — the game before it had bodies |

> **The rig must be named exactly `Noob`.** Roblox's Rig Builder inserts one
> called `Dummy`, and `NoobBlock.template()` looks the name up directly — a rig
> that is otherwise perfect but still called `Dummy` fails the lookup, and the
> failure is *silent by design* (a missing rig costs the joke, not the turn). If
> Noobs never appear, check the name before anything else. This is exactly how it
> broke the first time.

| `Assets.Sounds.BombBeep` | A short `Sound`, the bomb's warning beep | The fuse still flashes red, just silently |
| `Assets.Sounds.Anvil` | A `Sound`, the Anvil type's landing clang | The Anvil lands on its skin's ordinary impact sample instead, and the cue library warns once |
| `Assets.Sounds.StormAmbience` | A looping-friendly `Sound`, the weather coming in. Tune its Volume in Studio — the ramp scales that value | The storm arrives silently (one warning); the clouds and the lightning still run |
| `Assets.Sounds.Impacts.<Material>` | A folder per material holding interchangeable impact takes — shipped: `Needoh`, `Wood`, `Grass`. Any number of `Sound`s; one is rolled per landing | That skin falls back to its single `impactSound` id, and warns once |
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
  `player.ReplicationFocus` on join, to a shared invisible `StreamingFocus` part
  that **rides the tower** (see below). Turning `StreamingEnabled` off in
  Workspace works too, and makes all of it redundant.

#### The streaming focus rides the tower

A client is only sent parts within `StreamingTargetRadius` (1024 studs by
default) of its replication focus. Pinning the focus to the *base* — which is
what this used to do — meant the sphere never moved: past roughly 800–1000 studs
of altitude the blocks at the top stopped being replicated at all, and the tower
went invisible while the HUD kept counting.

`updateStreamingFocus` runs on the poll and parks one shared part at the middle
of the **live span** — the current floor (`zoneBaseHeight`) up to the top. One
part serves everyone because everyone is looking at the same tower.

Centring on the live span is what makes this safe indefinitely rather than just
buying more headroom. Every checkpoint demolishes the floors below it, so what
exists at any moment is *one stage's climb* (`stormGap`, 40 studs and growing by
5) — a few hundred studs at most, comfortably inside the radius no matter how
high the run's absolute altitude has got. Pieces spawn above the top and debris
flies past it; both are well within the sphere at that distance.

It's updated outside `updateHeight` on purpose: that returns early through a
checkpoint or a round break, and the focus has to keep tracking through both —
the demolition and the wreck are the parts of the game most worth seeing.

The part is `CanQuery = false` as well as invisible, because the landing preview
casts straight down the play plane and a marker sitting in it would read as a
surface the piece could land on.

**What this does *not* fix** is float precision, which is a property of absolute
altitude rather than of the tower's size. Roblox is comfortable to a few thousand
studs and starts visibly jittering somewhere past ~10,000; with gaps growing 5
per checkpoint that's about **50 checkpoints** into a single unbroken run. If
runs ever get that long, the fix is to periodically shift the whole arena back
down and keep the displayed height as an offset — a real technique, but one that
buys nothing until a run actually reaches that altitude.

`Constants.DISABLE_CHARACTERS` is what turns avatars off (`CharacterAutoLoads`).
Flip it to `false` if you want walking players; nothing else depends on it.

## Controls

Every surface calls the same four `TowerController` intents, so adding an input
device is additive.

| Intent | Keyboard / mouse | Gamepad | Touch |
| ------ | ---------------- | ------- | ----- |
| `setSteer(-1)` | hold A / ← | left stick, DPadLeft, or **L1** (LB) | **LEFT** button (pulse) |
| `setSteer(1)` | hold D / → | left stick, DPadRight, or **R1** (RB) | **RIGHT** button (pulse) |
| `aim(x)` | move the mouse | — | — |
| `rotate` | W / ↑ / R / scroll wheel | **L3** (stick click), **L2** (LT), or ButtonY | **TURN** button |
| `drop` | Space / S / ↓ / left click | **R2** (RT), or ButtonA | **DROP** button |

The **right stick is not a piece control**. It drives the player's cursor — see
[Cursors](Cursors.md) — and on console that cursor is the only pointer they have,
so nothing here may take the stick back.

The HUD shows the matching list in the bottom-left corner for `HINT_SECONDS`
(60), then fades it out — new players get told once, everyone else gets their
screen back. **Which list it shows follows the input the player is actually
using**, not what the machine has: `TowerView.useDevice` starts from capability
and then tracks `LastInputTypeChanged`, because a PC with a controller plugged in
reports both `KeyboardEnabled` and `GamepadEnabled` and would otherwise show
keyboard hints to someone holding a pad. `Focus` and `TextInput` are ignored —
they fire from window focus and the chat bar and say nothing about what's in the
player's hands.

### The left stick

Every gamepad binding is an **alternative**, never a mode: the D-pad, the
bumpers and the stick all steer, and L3 / L2 / Y all rotate. A player can move
between them mid-turn and the game doesn't care which they used last.

**Left stick — steer, analog.** `setSteer` takes anything in `[-1, 1]` and the
render loop integrates it, so a gentle push nudges the piece and a full one moves
it at `STEER_SPEED`. The value is *clamped, not rounded* — rounding is what would
throw the analog range away and make the stick behave like a D-pad. Below
`GAMEPAD_STEER_DEADZONE` the stick reads as centred and control hands back to the
D-pad or bumpers on that frame, so releasing it doesn't leave the piece gliding
on the last analog value or stomp a direction still being held.

The stick is the one thing ContextActionService can't express: it delivers a
stick as a stream of Change events, and this needs frame *state* — an analog
value to integrate. It's read from `GetGamepadState` in a Heartbeat instead. A
stick held at a constant angle fires no events at all, which is why polling is
the only correct read.

`L2` and `R2` are analog triggers, but Roblox reports them as buttons too, and
`bind` only ever acts on `Begin` — so a trigger pull is one quarter turn (or one
drop) rather than a stream of them as it travels.

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
| `Packets.luau` | shared | ByteNet: `Place`, `Release`, `State`, `Announce`, `AfkNotice` |
| `BlockSkins.luau` | shared | Look + sounds per skin, with rarity weights |
| `BlockTypes.luau` | shared | The twelve block types, their descriptions, the odds curve, and the Mystery pool |
| `BlockLabel.luau` | shared | The world-space name plate, and `titleFor` — the one place a piece is named |
| `NoobBlock.luau` | shared | The Noob rig: build, wander, squash. Server-only in practice |
| `BlockBody.luau` | shared | The rounded shell: the template lookup and the offset that seats one over a piece's cubes |
| `TowerBodyController.client.luau` | client | Builds each block's body client-side, hides the cubes under it, mirrors their look, and runs the squash spring |
| `Zones.luau` | shared | The seven zones, their skies, and their gravity |
| `CheckpointQuest.ui.luau` | shared | The quest line: promises the rare skin, then names it once it lands |
| `CheckpointQuest.story.luau` | shared | UI Labs story — the only place to see the claimed side, which happens once ever in game |
| `CheckpointQuestService.server.luau` | server | Hands the rare skin over on a player's first checkpoint, then closes the quest |
| `DuckSkinService.server.luau` | server | Grants `skins.duck` to the accounts in `Constants.DUCK_OWNERS` and to nobody else |
| `PlayerData.luau` | shared | Registers the `TowerGame` profile slice |
| `Gamemodes.luau` | shared | The three votable modes and the stage numbers each one sets |
| `Gamemode.luau` | shared | Registers those modes into GamemodeVote (auto-discovered) |
| `SkinPacks.luau` | shared | The buyable block looks and the material each one forces |
| `Store.luau` | shared | Registers the coins currency, the skin packs and the Robux products into the Store (auto-discovered) |
| `TowerService.server.luau` | server | Arena, turn queue, held piece, physics, height, storm — the whole authority |
| `TowerStatsService.server.luau` | server | Profile reads/writes + the leaderstats mirror |
| `TowerProductsService.server.luau` | server | What the Nuke / Next Checkpoint / Extend Storm products actually do, and the chat announcement each one sends |
| `TowerProductsPresentation.client.luau` | client | The two Robux buttons in the rail's "actions" cluster |
| `TowerAnnounceController.client.luau` | client | Renders those purchases as a system message in the general chat channel |
| `TowerController.client.luau` | client | State store (`GetData` + `DataChanged`) + the wire |
| `TowerAimController.client.luau` | client | The local preview and everything that makes aiming feel instant |
| `TowerInputController.client.luau` | client | Keyboard + gamepad binds |
| `TowerPointerController.client.luau` | client | Mouse aiming + click-to-drop (PC) |
| `TowerCameraController.client.luau` | client | Scriptable camera riding the tower's altitude, the checkpoint pull-back, and the storm shake |
| `TowerView.client.luau` | client | Container: subscribes via `useReplica`, runs the clocks, picks the device |
| `TowerAfkController.client.luau` | client | Whether the inactivity card is up, and the two answers to it |
| `TowerAfkView.client.luau` | client | Container for the card; renders nothing while it's down |
| `TowerSpectatorView.client.luau` | client | Container for the badge, on its own root so it can draw *under* the HUD (`ui.layers.underlay`) |
| `TowerAfkPresentation.client.luau` | client | Registers both as always-mounted roots (`Presentations.afk` gates the pair) |
| `AfkNotice.ui.luau` | shared | Dumb card: the copy, the red / green pair, the screen cover |
| `SpectatorNotice.ui.luau` | shared | The badge that stays up while a player is out of the rotation, with the PLAY button back in |
| `TowerHUD.ui.luau` | shared | Dumb HUD (turn strip, clocks, climb rail, hint, touch controls, Extend Storm, the urgency tick) |
| `TurnStrip.ui.luau` | shared | Headshot row, current player centered |
| `ProgressLine.ui.luau` | shared | The climb rail down the right edge: start / goal dots and a marker carrying the height readout. Can cap the goal with a deadline (`goalLabel`); TowerGame's HUD doesn't |
| `ProgressLine.story.luau` | shared | UI Labs story — drag `current` and watch the marker glide |
| `ControlsHint.ui.luau` | shared | Bottom-left control list that fades out |
| `StormFade.ui.luau` | shared | The storm's one-shot white-out, played on `PHASE.GAMEOVER` |
| `SteerStick.ui.luau` | shared | Touch steering: a horizontal drag track reporting analog `[-1, 1]` |
| `SteerStick.story.luau` | shared | UI Labs story — drag it with the mouse, with a live value readout |
| `TowerHUD.story.luau` | shared | UI Labs story — every prop on a slider, including both clocks |
| `StormFade.story.luau` | shared | UI Labs story — replays the white-out on demand |
| `TowerStormController.client.luau` | client | The storm approach: ambience, terrain clouds and background lightning, all off one ramp |
| `LightningBolt.client.luau` | client | Draws a branching bolt by midpoint displacement. Shared by the background VFX and the Stormy zone's strike |
| `TowerPresentation.client.luau` | client | Registers the HUD and the cash readout as UIRegistry **roots** |
| `TowerCashView.client.luau` | client | The cash counter + payout burst, on `ui.layers.flourish` so it draws over any open window |

## The HUD

```
          (⚡)  ( o ) (O) ( o )  (◕)        Extend Storm | turn strip | turn clock
                                                      Storm in 3:42
    Get to the next checkpoint for a RARE skin!                       ○  next zone
                       (new players only)                             │
                                                       24.5 studs ─● │  the tower
                                                                     ●  leg start
  Move — A / D…        Your turn — Bomb T-Shape       [LEFT][TURN][RIGHT][DROP]
  (fades after 60s)                            $ 1,250   (touch only)
```

**The top column is one row and no surface** — a strip of headshots, the storm
clock under it, and the new-player quest notification under that for six seconds. It used to be four rows: turn strip, a
panel holding the height beside a best-ever reading, the progress bar, and the
storm clock — which on a phone is a stack of chrome sitting on top of the thing
the player is aiming at. The height moved onto the climb rail's marker, the
best-ever reading was dropped (it's a number nobody can act on mid-drop, and the
server still keeps it — `state.maxHeight` is what cash is paid against), the panel
behind them went with them, and the storm clock moved onto the rail as well.

**The storm clock is in the top column**, under the turn strip. It spent a while
capping the rail instead, on the argument that how far up the climb is and how long
is left to finish it are one question and belong on one object — which is still
true, and still lost to where players actually look. The rail is at the right edge
and read in glances; a deadline is the one number on this HUD that has to be
readable without going to find it, so it sits where the eye already is. It goes red
under `STORM_URGENT_SECONDS` (30) either way.

`ProgressLine.goalLabel` still exists and still reserves its band out of the rail's
own height when set — the HUD just passes nothing, so the rail is the climb alone
and gives that band back to the track. Its story is where the capability is
exercised now.

The **turn clock is a plain circle** (`RadialTimer`), only existing while
someone is aiming. Two radial-fill treatments were tried first — a filling pie
and a hollow ring, both built from `UIGradient` hacks to fake a radial sweep
since Roblox has no native one — and neither read well in practice, so the dial
is a solid circle with the seconds label on top; its colour still shifts red
under `URGENT_SECONDS`.

**The touch controls are only up on your own turn.** They used to stand there
greyed out through everybody else's, which is a control saying "not now" where
the player wanted a screen saying nothing — and on a phone it's the bottom third
of the display spent saying it. The row renders on `showControls and canAct`;
nothing inside it carries a `disabled` any more, because that state is now
unreachable.

The *space* is still reserved for the whole round: the status line's offset is
keyed on `showControls` (the device answer, fixed for the session) rather than on
whether the row is up this second — see the rule below. PVP is deliberately left
alone, because it has no turns: a player there is between pieces for a second or
two at a time, and a control row that blinked out every few seconds would be
worse than one that dims.

### Nothing that comes and goes may move what stays

The dial and the Extend Storm button **flank** the turn strip at `FLANK_Y`,
positioned absolutely *outside* the column rather than laid out inside it.

This is the fix for a real bug, not a style choice. The dial used to sit in a
row beside the stats panel, so the panel had to give up width for it — which
meant the height readout resized *and* slid sideways twice a turn, every turn.
Worse, mid-tween the row was briefly wider than the column and centred itself,
shoving the panel a further half-dial to the left. The panel is gone now, but
the rule it taught isn't: both flanks clear the **column's** width rather than
the turn strip's own, so headshots coming and going either side of the holder
can't move them.

The dial **pops in** on mount — a `UIScale` tweened 0 → 1 on `Back/Out`, so it
reads as arriving rather than fading up. Its appearance is the cue that a turn
started, which is worth animating.

The last `URGENT_SECONDS` (5) of a turn **tick audibly** (`audio.playUI("tick")`).
Keyed on the whole second rather than the raw countdown, and latched so a
re-render inside the same second can't double it up; the latch clears whenever
the countdown leaves the window, which re-arms it for the next turn without
having to watch the turn itself.

The **climb rail** (`ProgressLine`) measures *this leg of the climb only* — from
`zoneBaseHeight` (where the current zone started) to `targetHeight` — so a run
always begins at the bottom dot no matter how tall the tower already is. The
tower is a dot for now; it's a separate element rather than a bar fill precisely
so it can grow into a little stack later.

### The first-checkpoint quest

**The game's one retention mechanic**, and the only place it pays a player for
playing rather than for spending. Roughly **70% of new players stop before their
first checkpoint** — it's the steepest drop-off in the game — so the climb up to
it is the one stretch worth buying outright.

A gold line under the storm clock says **"Get to the next checkpoint for a RARE
skin!"** for `QUEST_PROMISE_SECONDS` (6), and clearing a checkpoint hands over
`skins.gold` — **Golden Blocks** (see [Skin packs](#skin-packs)).

**It's a notification, not a standing line.** It used to sit in the column for as
long as the player hadn't earned the skin, which is where the storm clock now
lives — and a permanent call to action was the wrong shape for it regardless. It's
news the first time and furniture by the tenth, so it announces itself once and
gets out of the way. Six seconds is long enough to read twice.

It fires **once per profile load**, the moment `useCheckpointQuest` learns the
player hasn't earned it — which for almost everyone is as they join. Not once per
round: a player told twice has been told, and the line is asking for something that
takes a whole stage to do. If it should nag per-round instead, the trigger is the
`phase` dependency in that hook.

It's a **bare label, not a panel**. A gem surface was tried first and read as a
separate widget parked on top of the HUD rather than as part of the block of text
describing the climb. Colour carries the whole distinction instead — gold while
it's a promise, green once it's paid — and the line is deliberately *unwrapped*
and wider than the top column, centred on it so it overruns evenly, exactly like
the status line at the bottom of the screen.

Five things keep it honest:

- **The prize can't be bought.** `skins.gold` is `forSale = false`, so it gets no
  shop card and `StoreService` refuses to sell it (see
  [Store § Reward-only packs](Store.md#reward-only-packs)). That's what makes
  "RARE" a fact rather than marketing — a reward also sitting in the shop for 60
  coins is not a reward.
- **One definition of what's promised.** `Constants.FIRST_CHECKPOINT_PACK` is the
  id the server grants *and* the id the HUD resolves the display name from, so the
  line cannot congratulate a player with a skin nothing hands over. The coins on
  the claimed side read off `Constants.CASH_PER_ZONE`, the constant `CashService`
  pays from.
- **The grant is server-side.** `CheckpointQuestService.award()` is called from
  `runCheckpoint`, right beside the payout it advertises. It grants to **everyone
  in the server** who qualifies — one shared tower, one shared moment, the same
  rule `recordHeight` follows — through `StoreService.grantPack`, the one blessed
  way a pack ever arrives.
- **The order inside `award()` is load-bearing.** It grants *first* and calls
  `TowerStatsService.recordCheckpointSeen` *second*, because that flag is what
  `isFirstCheckpointFor` reads — flipping it first would close the quest on every
  player a line before paying them. A player whose profile hasn't loaded is
  skipped rather than granted against nothing; they earn it on the next floor.
- **Earning it takes the promise down early**, whatever is left on its six
  seconds. The claimed line is about to stand where the promise was, and two of
  these at once would be the game promising and paying in the same breath.
- **It's shown to new players only, then held one beat longer.**
  `SeenCheckpoint` on the profile slice (see
  [Stats and saving](#stats-and-saving)) is what qualifies them. The line doesn't
  vanish when the flag flips — `TowerView.useCheckpointQuest` watches the replica
  for the false → true transition and flips the line green for
  `QUEST_CLAIMED_SECONDS` (8), naming what they won, before it goes for good. A
  promise whose payoff is invisible teaches players that promises here are
  invisible; the reveal is the point. It only celebrates a transition it actually
  watched happen, so a profile that loads already-true never congratulates a
  veteran for a skin they earned months ago.

The line sits **below the turn strip** in the top column — the last row of it,
which is what keeps it inside the rule above: it comes and goes, but everything it
could move is above it, and the column is anchored at the top. Nothing that stays
moves when a new player's line appears or a veteran's never does.

Note for an existing place: `profile:Reconcile()` backfills `SeenCheckpoint` as
`false` for players who predate it, so **veterans get the line and the free skin
on their next checkpoint**, once. If that's not wanted, backfill the flag as
`true` for existing profiles before shipping.

**It runs vertically, down the right edge**, because the thing it measures does:
the tower goes up, the marker goes up. The **height readout is a child of that
marker** rather than a readout elsewhere on the screen — how high the tower is
and how far through the stage that is are the same fact, so one tween moves both
and they can't disagree.

The rail is inset `RAIL_RIGHT` (96) from the edge rather than flush to it: the
[Reactions](Reactions.md) column opens down that edge vertically centred and the
two would overlap. That number is hardcoded in `TowerHUD` with a note — a feature
can't reach into another feature's constants, and the rail only has to be *clear*
of it. `RAIL_TOP` clears Roblox's own topbar (the root ScreenGui sets
`IgnoreGuiInset`, so y = 0 is the true top of the display) and `RAIL_BOTTOM` is
derived from the camera toggle and cash counter stacked in the corner below.

**The storm clock and the rail both go whenever no stage is running** — `GAMEOVER`
or `IDLE` — behind one flag, `stormRunning`, so they can't disagree.

`GAMEOVER` is the round break: the round is over, the tower they measured is
wreckage, and the server has frozen `stormEndsAt` — but the client draws the clock
as `stormEndsAt - now`, so leaving it up counted a dead deadline down behind the
gamemode vote and then snapped back when the next round started.

`IDLE` is the same nothing from the other end: nobody is in the queue, so the
server holds the clock instead of ticking it. That's the phase the **opening vote**
runs under — the first ballot of a server has no round behind it to end, so it
never passes through `GAMEOVER` — and the rail used to stand there right through
it, reading a frozen deadline over an empty platform.

The phase is the right test for this: the HUD never learns that a vote is up (that
belongs to [GamemodeVote](GamemodeVote.md), and this file doesn't know that feature
exists), only that no stage is running. Both stay up through a **checkpoint**,
where the rail showing the leg just built is the point of the moment.

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

`Announce` is the one packet that isn't about the tower: server → all, two ids,
sent when an action product's effect has actually applied. See
[the chat announcement](#the-chat-announcement).

## Tuning

Everything is in `Constants.luau`. The knobs worth reaching for first:

| Constant | Effect |
| -------- | ------ |
| `TURN_SECONDS` | The drop clock (15) |
| `FIRST_CHECKPOINT_PACK` | Which pack the first-checkpoint quest hands over. Must be a `forSale = false` entry in `SkinPacks.List`, or the prize is buyable and the line is lying |
| `QUEST_PROMISE_SECONDS` | How long the promise line stays up before it clears itself (6) |
| `QUEST_CLAIMED_SECONDS` | How long the quest line stays up naming the prize after the grant lands (8) |
| `DUCK_PACK`, `DUCK_OWNERS` | The Duck skin's pack id and the exact usernames it's granted to. The list is the entire access control for it — see [The Duck skin](#the-duck-skin) |
| `IDLE_TURN_SECONDS`, `IDLE_GRACE_TURNS`, `IDLE_TURNS_BEFORE_AFK` | The short clock for an untouched turn (6), how many of a player's first turns are exempt (1), and how many untouched turns in a row bench them (2) — see [Idle turns](#idle-turns-and-the-inactivity-card) |
| `EDGE_MARGIN` | How far anything pinned to a screen edge sits in from it (20). Shared by the HUD and the spectator badge so the two can't disagree |
| `SPECTATOR_NOTICE_WIDTH`, `SPECTATOR_NOTICE_TOP`, `SPECTATOR_NOTICE_COLOR` | The spectator badge. `TOP` hangs it below the HUD's top column; the GUI inset is added on top of it at render |
| `SETTLE_SECONDS` | Pause between turns |
| `STEER_SPEED`, `STEER_LIMIT_X` | How fast a piece slides and how far off-center it can get |
| `GAMEPAD_STEER_DEADZONE` | Below this the left stick reads as centred and the D-pad / bumpers take over (0.2) |
| `SPAWN_CLEARANCE` | Clear air under a fresh piece, measured from its lowest possible point — see [The held piece](#the-held-piece) |
| `STORM_SECONDS` | The first stage's clock (300) |
| `STORM_TIME_GROWTH` | Seconds added to the stage clock per checkpoint cleared (5) |
| `STORM_FIRST_TARGET`, `STORM_GAP_GROWTH` | First checkpoint at 40 studs, each next gap 5 further. Tune them against the ~18-turn stage budget, not on their own — see [The storm](#the-storm) |
| `STORM_BLAST_*` | How hard the storm throws the tower, and how long the debris flies |
| `CHECKPOINT_*_SECONDS` | The four beats of the checkpoint cutscene. Total pause is their sum plus `PLATFORM_GROW_SECONDS` |
| `CHECKPOINT_BLAST_*` | How hard the old tower is thrown when the new floor lands |
| `BlockTypes.BASE_CHANCE` / `PER_CHECKPOINT` / `MAX_CHANCE` | How often a block is special. **Note the cap** — raising `BASE_CHANCE` alone does nothing past `MAX_CHANCE` |
| `BOMB_BEEPS`, `BOMB_BEEP_ON/OFF`, `EXPLOSION_VOLUME` | The bomb's fuse and how loud the payoff is |
| `NUKE_BLASTS`, `NUKE_BLASTS_ACROSS` | Rungs up the tower × blasts abreast at each rung. The first makes it climb, the second makes it cover the plane |
| `NUKE_BLAST_JITTER`, `NUKE_BLAST_INTERVAL` | How far a blast wanders from its column, and the beat between rungs |
| `NUKE_WRECK_SECONDS` | How long the wreck flies after the **last** blast before it's swept |
| `BURN_SECONDS`, `BURN_SPREAD_RADIUS`, `BURN_SPREAD_DELAY` | How long a burning block lasts and how eagerly it passes it on |
| `BURN_MAX_SPREAD` | Other blocks one fire may take, across the whole chain (3). Not per block |
| `CLONE_RISE`, `CLONE_OFFSET_X` | Where a Clone's copy drops in from |
| `BOUNCY_PHYSICS` | How much a Bouncy block bounces |
| `ANVIL_PHYSICS`, `ICE_PHYSICS`, `FEATHER_PHYSICS` | The other three physics types. Density survives a Snowy zone; friction and elasticity don't |
| `FEATHER_FALL_SPEED` | A Feather's terminal velocity (12). The actual mechanic — density can't slow a fall |
| `FALL_SPEED` | Terminal velocity for every other block (55). Turn it down for softer landings, up towards 70 for the old punch |
| `CRATE_SCATTER`, `CRATE_LIFT`, `CRATE_SPIN` | How far a broken Crate's cells throw themselves apart. In-plane only |
| `GHOST_SECONDS`, `GHOST_TRANSPARENCY` | How long a Ghost phases for, and how see-through it is while it does |
| `BLOCK_COLLISION_GROUP`, `GHOST_COLLISION_GROUP` | The two groups that let a Ghost ignore blocks without ignoring the floor |
| `MAGNET_RADIUS`, `MAGNET_ACCEL`, `MAGNET_SECONDS`, `MAGNET_LIFT` | Reach, strength, duration and upward tilt of a Magnet's pull field. It's an acceleration re-applied per frame, not an impulse — see the Magnet note for why two rounds of raising an impulse were invisible |
| `SACRIFICE_REACH`, `SACRIFICE_VOLUME` | How far under itself a revealed Sacrifice looks for what it's resting on, and how loud unmaking a block is (its own `Sacrifice` cue at **1.5**, a shade under a Bomb's 1.7 — it opened at 0.6, which was set against the explosion it used to borrow and left the softer dedicated cue inaudible under a landing) |
| `SACRIFICE_FADE_SECONDS`, `SACRIFICE_FLASH_SECONDS`, `SACRIFICE_HOLD` | The send-off's clock: how long the taken block takes to go, how fast it flashes to `SACRIFICE_GLOW`, and how much of the fade it spends at full opacity first |
| `SACRIFICE_RISE`, `SACRIFICE_DRIFT`, `SACRIFICE_SPIN` | How it leaves — studs/second up, studs/second away from the block that took it, radians/second of tumble about Z |
| `SACRIFICE_GLOW`, `SACRIFICE_CORPSE_NAME` | The colour it glows (the type's own tell) and what the drifting copy is called in the arena |
| `MYSTERY_REVEAL_SECONDS` | How long the revealed name hangs over a Mystery block |
| `NOOB_*` | Walk speed, jump odds, and how long a squashed Noob lies there |
| `SETTLE_CONFIRM_SECONDS`, `UNSETTLE_SPEED/SPIN` | How long a block has to hold still to count, and what knocks it back out |
| `IMPACT_MIN_SPEED`, `IMPACT_LOUD_SPEED` | What counts as a landing, and what counts as a hard one |
| `AVATAR_*` | Turn-strip sizing, spacing and fade |
| `HINT_SECONDS`, `HINT_FADE_SECONDS` | How long the controls list stays, and how fast it goes |
| `PLATFORM_SIZE` | Size of the base *and* every checkpoint — they're the same slab |
| `PLATFORM_GROW_SECONDS`, `PLATFORM_FADE_SECONDS` | The checkpoint entrance tween |
| `BLOCK_PHYSICS` | Friction / density / bounce of every block |
| `FLOOR_PHYSICS` | The same, for the base / checkpoints / PVP lane platforms, with both weights at 100 so the ground wins its own contacts |
| `CAMERA_DISTANCE`, `CAMERA_AIM_LIFT`, `CAMERA_LERP` | Framing and follow feel on a desktop |
| `CAMERA_DISTANCE_TOUCH`, `CAMERA_AIM_LIFT_TOUCH` | The same two for a phone — see [Camera](#camera) |
| `CAMERA_CHECKPOINT_*` | The wide shot: how slowly it eases, how much headroom, and the floor and ceiling on how far back it goes |
| `CAMERA_PIECE_MARGIN` | Headroom kept above the piece being aimed |
| `CAMERA_MIN_HALF_WIDTH` | Half the play area the camera must show across, on any aspect ratio |
| `DESPAWN_BELOW` | How far under the platform a fallen block is cleaned up |

The HUD is a full-screen gameplay surface, so it hugs the edges rather than
following the centered-by-default rule for feature UIs — centering a height
readout would put it on top of the tower the player is aiming at.

## Zones

Clearing a checkpoint moves the run into a new zone. The server picks it and
broadcasts the id; the server owns the half that can't be faked (how blocks
*feel*), the client owns the look. Both read the same `Zones.luau` table.

| Zone | Blocks | World |
| ---- | ------ | ----- |
| Clear Skies | unchanged | a random sky from `Assets.Zones.Normal` |
| Retro | old stud look — Plastic, **studs on all six faces** | — |
| Snowy | slippery (friction 0.05) | snowfall |
| Stormy | struck blocks are destroyed | rain, plus **lightning** that detonates where it lands |
| Space | unchanged | `workspace.Gravity` drops to **30** |
| Foggy | unchanged | `Lighting` fog closes in to `FOG_END` |
| Night | each gains a `PointLight` in its own colour | dark: `Brightness`, `Ambient` and `ClockTime` drop |

Only special zones announce themselves — a normal zone is just a new sky. That
test is `Zones.announces(zone)` (`kind ~= "normal"`), not "does it have copy": it
used to be the latter, which stopped working the moment every zone needed a line
for PVP's reel to print. The banner clears itself after `ZONE_WARNING_SECONDS`.

**A zone has exactly one line, its `warning`,** and every surface prints that one:
this banner, and the card under PVP's zone reel — see
[TowerGamePvp.md](TowerGamePvp.md) § "The zones". There was a second, longer
`description` field written mode-neutral; it's gone, because two strings per zone
is two places for a zone to describe itself and they drifted. Clear Skies has a
line of its own now ("Clear skies — nothing bends the rules!") for the reel to
land on; it just doesn't banner. Stormy's line — the one that used to strain,
because it names lightning — is true in both modes now that
[a match has its own storm](TowerGamePvp.md#the-storm).

### The cadence

Zones arrive on a **rhythm, not a roll**: `Zones.next` returns a normal zone
unless `(cleared + 1)` is divisible by `NORMALS_PER_SPECIAL + 1`, which puts a
special every third zone — two calm floors, then a twist.

A weighted roll (what this replaced) can hand out four specials in a row or none
for six floors, and neither is the shape of a run anyone wants. *Which* special
comes up is still random, and `avoidId` stops the same one landing twice running.

Normal zones therefore never roll *here*, but their `weight` is read elsewhere —
`Zones.roll` (PVP's clock-driven pick) rolls the whole list, weights and all.

`Zones.rollSpecial(avoidId)` is the second half of `Zones.next` on its own: the
weighted roll over the specials, with no cadence in front of it. The cadence
decides *whether* a special is due; this decides *which*. The **Wild Weather**
gamemode (`specialsOnly`) calls it directly on every checkpoint — and once more
when the round opens, because the first stage is the longest one and a
specials-only round that started in Clear Skies would spend it playing like
Classic. See `applyOpeningZone` in TowerService.

### Stormy: lightning

Every `LIGHTNING_MIN_SECONDS` to `LIGHTNING_MAX_SECONDS`, the storm picks a
**random spot** on the play plane, stands a pulsing blue column on it for
`LIGHTNING_WARNING_SECONDS` (10), and *then* detonates.

The warning is the mechanic. An unannounced strike is a tax; an announced one is
a decision — you can see where the bolt is going and choose whether to keep
building into it. A *place* is picked rather than a block precisely so the
warning can appear before anything is standing there.

The gap is measured from the previous strike and the warning sits **inside** it,
so raising `LIGHTNING_WARNING_SECONDS` doesn't quietly slow the storm down. The
marker is cleared before the bolt lands, and again if the zone changes mid-warning
— otherwise a column would be left standing over a zone with no lightning in it.

**The marker stands on the current floor, and the client decides where that is.**
`WARN_ATTRIBUTE` carries only the X: the column is `WARN_HEIGHT` (400) studs tall
and has to start at the floor the run is *currently* building from, which moves up
every checkpoint. `TowerZoneController` stands it at `BASE_TOP_ATTRIBUTE +
zoneBaseHeight` — the same pair the camera frames its shots from, so the marker is
always inside the shot — and re-seats it on the same 0.5s poll the weather uses, so
a checkpoint landing mid-warning takes the column up with it.

Sending the arena's *base* instead (what this replaced) worked for the first stage
and then quietly stopped: a few floors in, the base sits hundreds of studs below
the play area, so the column was drawn correctly and framed entirely off-screen.

The blast goes through the same `blastAt` the Bomb type uses, so a strike behaves
the way players have already learned bombs behave and there's one blast to tune.
It's deliberately smaller than a bomb (`LIGHTNING_RADIUS` 26 vs `EXPLOSION_RADIUS`
36): a bomb is a piece the players were handed and can plan around, while this
arrives unasked.

**Three of the assumptions above are the classic run's, not the bolt's**, and
`TowerService.strikeColumn(x, floorY, source)` is the same strike with them made
into arguments: which floor an empty column falls back to, and which instance
announces the flash and the marker. A PVP match calls it once per lane from its own
clock — see [TowerGamePvp.md § The storm](TowerGamePvp.md#the-storm) — which is why
`highestAt` takes a floor and `strikeLightning` takes an announcer. The driver
above stays single-lane and stays switched off for a match; it still clears its own
marker there, because a zone can turn stormy in the last seconds of a round and the
match that follows must not inherit a column standing over a tower that no longer
exists.

**Two dials, and they aren't interchangeable.** `LIGHTNING_IMPULSE` (43) is how
hard it hits — `blastAt` throws every block in range by hand, because
`BlastPressure` barely moves a welded assembly, so that number is the strike's
whole bite and scaling it scales the damage directly. `LIGHTNING_RADIUS` is how
*wide* it reaches, and it's much blunter: it decides which blocks are touched at
all and shapes the falloff, so halving it leaves roughly a fifth of them hit
rather than half.

The **Lightning Storm** gamemode (`alwaysLightning`) turns it on in every zone for
a whole round. It keeps the ten-second warning, so it's round-long pressure rather
than an unfair one.

The server writes the strike position to the `STRIKE_ATTRIBUTE` on the arena and
every client draws its own bolt off it. Attributes replicate, so the flash costs
no packet of its own, and a client that misses it simply doesn't draw one.

**This replaced a constant wind.** Wind applied every frame to every block, so
there was no moment to react to — the tower slowly argued with itself and nothing
a player did changed that. A strike lands somewhere specific, you see it happen,
and the damage is local.

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
names no gravity and gets `Zones.DEFAULT_GRAVITY` (160) back. `resetRun` and
`Start` both set it, so a run never inherits the last one's physics — or the place
file's.

Two more details worth keeping:

- **Zone dressing is the server's word, and it's the same for the whole room.**
  A skin pack rides on the block rather than on the viewer — see
  [Skin packs](#skin-packs) — so a bought cosmetic changes that player's blocks
  for everyone, and nobody else's for anyone.
- **The server sends an arbitrary number for the sky, not an index.** It has no
  idea how many skies exist — that's a Studio asset it can't see — so the client
  takes it modulo the folder count. Adding a sky in Studio needs no code change.

**Fog and darkness are `Lighting` properties, so they're purely local.** The
server never touches Lighting; `TowerZoneController` captures what the place file
had on the first zone change and restores from that, rather than from a second
set of hardcoded numbers that could drift away from it.

Night's block lights are client-side decoration too — one `PointLight` per
*block*, hung on the model's first part rather than on every cell (four lights on
a tetromino cost four times as much and look the same), tinted the block's own
colour so a tower of mixed skins lights the arena in what the players built with.
Blocks arrive constantly, so the 0.5s sweep that keeps the weather above the
tower also lights anything placed *during* the night.

All the zone assets live under `ReplicatedStorage.Assets` and are **Studio-
authored — Rojo doesn't sync them**. Every lookup degrades to "leave it as it
was": a missing skybox costs you a nice sky, not the game.

## Landing feel

Three numbers decide whether a placement that *looks* right survives, and they
were all tuned together — moving one without the others undoes the change.

| Lever | Was | Now | What it does |
| ----- | --- | --- | ------------ |
| `BLOCK_FRICTION` | 0.9 | **1.2** | Grip. One local at the top of `Constants.luau`, shared by `BLOCK_PHYSICS`, `FLOOR_PHYSICS`, `ANVIL_PHYSICS` and `FEATHER_PHYSICS` — four surfaces that must not disagree, or a block grips differently depending on what it happens to rest on. Ice opts out; sliding is the whole type. |
| `Zones.DEFAULT_GRAVITY` | 196.2 | **160** | Time. A leaning stack now topples slowly enough to be read as a lean, sometimes slowly enough for the next piece to catch it. |
| `FALL_SPEED` | — | **55** | Impact. A terminal velocity for every block, applied in the plane poll beside the Feather clamp it generalises. |

The cap is the one doing most of the work, and it is nearly free in time — a
terminal velocity only bites in the last stretch of a fall:

| Drop | Before | After |
| ---- | ------ | ----- |
| From `SPAWN_CLEARANCE` (14 studs) | 74.1 studs/s, 0.378s | **55.0 studs/s, 0.426s** — 55% of the energy, 13% slower |
| Past the stack, 60 studs | 153.4 studs/s | **55.0 studs/s** — 13% of the energy |

That second row is the case that used to end runs: a piece that missed its landing
arrived at three times the speed of a placed one and took the tower apart on the
way down. It now arrives at the same speed as everything else.

**`IMPACT_LOUD_SPEED` is pinned to `FALL_SPEED`** (both 55). It's the speed at
which a landing plays at full volume, and with a terminal velocity in play nothing
can ever arrive faster — leaving it at 70 would have muted every landing in the
game to 74% and thrown away the top of the range for a speed that no longer exists.

### How loud a landing is

Two gains stack on top of whatever the sample was tuned to, and they have
different scopes on purpose:

| Dial | Scope |
| ---- | ----- |
| `BLOCK_VOLUME_SCALE` (2) | Everything a *block* makes a noise about: the landing, the settle, the drop, the glue weld, the bomb's beep. Applied in `attachSound` and `playAtBlock`, so it can't be forgotten at a call site. |
| `IMPACT_VOLUME_SCALE` (2.5) | The **landing alone** — the skin's impact sample and the cue a type lands on instead. Applied in `playImpact`, to both paths. |

So a landing is 5x its tuned sample and everything else a block does is 2x. The
landing gets its own dial because it's the game's percussion: it's what the room
is listening for, it's the one with a folder of takes behind it, and it wants to
sit above the noises a block makes on the way there. Neither dial touches the
world SFX (the storm, lightning, a demolition, the nuke) — those aren't a block
being a block, and they were already the loudest things in the game.

Both multiply rather than replace, so the mix *between* materials — a squish
against a plank against an anvil's clang — survives any change to either.

## Cash

| Award | Who | Why |
| ----- | --- | --- |
| 50 per zone reached | everyone | the room cleared it together |
| 10 per five minutes | everyone | one shared clock |
| `CASH_PER_STUD` per stud of new record | whoever placed | they're the one who pushed it up |

The per-stud award pays the last dropper, tracked as `lastDropper`, whenever the
tower's record grows — so extending the tower earns, and the two shared awards
keep it from being purely individual.

Every one of them goes through `CashService.award`, which is also where the **2x
Cash** gamepass multiplies (see [Gamepasses](#gamepasses)) — one write path, one
place a multiplier can live.

There's no cash packet. It's persisted on the profile, so the replica diff *is*
the event: `TowerFeedbackController` watches the value, and an increase becomes
the sound plus a signal the HUD animates from. One source of truth, so the
counter and the flying bills can't disagree about how much arrived.

The bills themselves aren't React-driven — a dozen images moved through state
would re-render the HUD every frame of the burst. React owns the host frame; the
bills are plain instances handed to TweenService that clean up after themselves.

**The counter is one component, `CashCounter`, on a root of its own.** It pins
itself to the bottom-right and owns the `CashFly` target, so the corner and the
point the bills converge on can't drift apart. `Constants.CASH_WIDTH` /
`CASH_HEIGHT` live outside it because both HUDs stack their camera toggle directly
above the counter, and the classic progress rail ends above the pair — layout
numbers their neighbours need, not the component's private business. PVP had no
counter at all until it was given this one; a match pays out at the results panel,
so it is the mode where the number is most worth watching.

**It is mounted by `TowerCashView`, not by either HUD, and it sits on
`ui.layers.flourish`.** Inside the HUDs it was on the same layer as the game —
under every window in the experience — so a payout that landed while a window was
open played out entirely behind it: `CashFly` bursts from the middle of the
screen, which is exactly where an open window is. Claiming a daily reward was the
worst case and the most common one, because the moment a player most wants to see
coins arrive is the moment they pressed a button to get them. On its own root it
draws over any window, and it stops depending on which HUD happens to be up.

### Spending it

Cash is registered with the [Store](Store.md) as the **`coins`** currency, whose
balance lives at `{ "TowerGame", "Cash" }`. Store is told the *path* rather than
given a copy, so there's still one source of truth — `CashService` is the only
thing that pays out, and `StoreService` is the only thing that debits.

## Skin packs

`SkinPacks.luau` lists the block looks, in two families:

| Pack | Price | Effect |
| ---- | ----- | ------ |
| `skins.needoh` — Needoh Blocks | **not for sale** | Every block **is** the Needoh `BlockSkin` — glass, translucent, squish on every landing |
| `skins.neon` — Neon Blocks | 100 coins | Every block part becomes `Enum.Material.Neon` |
| `skins.gold` — Golden Blocks | **not for sale** | `Enum.Material.Foil` **and** a tight gold hue |
| `skins.duck` — Duck Blocks | **not for sale, not grantable by any quest** | Pins the Duck `BlockSkin` — tiled duck texture, a quack on every landing — **and** a tight yellow hue. See [The Duck skin](#the-duck-skin) |
| `skins.red` … `skins.black` (10) | 60 coins | Every block you place is a **random shade** of that colour |

A skin pack overrides the look of **the blocks its owner drops**. A pack that
owns the surface (Neon, Needoh, Duck) also overrides whatever the current zone
had dressed them in — a Retro zone can't dull a neon block or stud a Needoh one.
That override is the product; `SkinPacks.ownsSurface` is the one place that
decides which packs get it.

**Gold and Duck set both halves.** Every other entry picks a lane: Neon sets
`material`, Needoh pins a `blockSkin`, the ten colours set `hue`. Gold needs Foil
*and* the hue, because the hue alone would land it beside the
sixty-coin Yellow pack — which is exactly what a reward for surviving the game's
steepest drop-off must not look like. Its jitter is deliberately tight
(`saturationJitter` 0.1, `valueJitter` 0.08): gold that wanders is brass on one
block and lemon on the next, and the tower stops reading as one metal. It's
`forSale = false`, so the [first-checkpoint quest](#the-first-checkpoint-quest)
is the only way in.

### Needoh pins the roll instead of overriding it

`blockSkin` on a pack names a `BlockSkins.Skin.id`, and `TowerService.beginTurn`
swaps the rolled skin for that one before the piece is built. It's a different
lever from `material`: pinning carries the surface, the transparency **and both
sounds**, so Needoh Blocks is the only pack a player can *hear*. The `block`
cmdr command still wins over it — that's a debug pin and has to be able to show
any skin on demand.

Needoh is the daily run's grand prize (day 7 — see
[DailyRewards](DailyRewards.md)) and **nothing else**. It registers with
`forSale = false`, so the shop never cards it and the server refuses to sell it —
a grand prize you could have bought on day one isn't one. Its `price`
(`Constants.NEEDOH_SKIN_PRICE`, 250) is only what it *would* cost if it ever went
on sale; see [Reward-only packs](Store.md#reward-only-packs).

### The Duck skin

A personal cosmetic for two named accounts. It's the only thing in the game with
**no route in at all**: it isn't rolled (`weight = 0`), it isn't sold
(`forSale = false`), and no quest, zone or daily reward names it.

`DuckSkinService.server.luau` is the entire supply. On join it checks the
player's name against `Constants.DUCK_OWNERS`, waits for the profile to land,
then calls `StoreService.grantPack` — the same blessed path the gold skin uses,
so ownership is written in one place however it arrived. Granting it to someone
else is one line in that list.

| Thing | Where |
| ----- | ----- |
| Who gets it | `Constants.DUCK_OWNERS` — exact usernames, matched case-insensitively |
| The pack | `Constants.DUCK_PACK` / `skins.duck` in `SkinPacks.luau` |
| The look and sound | Skin id 8 in `BlockSkins.luau` |
| The grant | `DuckSkinService.server.luau` |

Usernames rather than UserIds, matching Cmdr's allow-list, with the same caveat:
a name change hands the skin to whoever picks the old name up. Acceptable for a
cosmetic in a way it wouldn't be for admin access — if that stops being true,
swap both lists to UserIds together.

**Removing a name stops the grant; it doesn't revoke.** A profile that already
owns the pack keeps it. Taking a cosmetic back off someone who has it equipped is
a different decision from not handing one out, and `DuckSkinService` doesn't make
it.

The quack is a **Studio-authored Sound**, not an id in `BlockSkins`. The skin
names it with `impactCue = "Quack"` and `BlockSkins.impactIdFor` resolves the
`SoundId` off the instance — looking in `Assets.Sounds` first (the house rule for
a sound a human tuned) and then in Workspace, memoized on the first hit so it
costs one lookup rather than one per landing. That resolver has three tiers, each
falling back to the next: `impactFolder` (a random take), then `impactCue` (one
named Sound), then the `impactSound` id. Only the *id* is ever taken, never the
instance — the skin owns its own volume and pitch range, and cloning the Sound
would put a second, quieter opinion about both onto every block. If the Sound isn't in the place
the skin falls back to the Classic knock and warns once: a missing asset should
cost the joke, not the landing.

### Colour packs roll a shade per block

The ten colours set `hue` and no `material`, so the rolled `BlockSkin`'s surface
(and its impact sounds) survive underneath the tint, and Retro can still stud them
over — a colour pack owns the hue, not the surface, so the two overrides never
have to fight.

**Each block rolls its own shade** (`SkinPacks.colorFor`) rather than taking one
flat value. A flat fill looks like a bug: forty identical blocks read as one solid
mass with no edges, and the tower stops being legible as a stack of pieces.
Varying saturation and value keeps every block's boundary visible while still
reading as "this player builds in red".

Hue wanders far less than the other two (`COLOR_SKIN_HUE_JITTER` 0.02) — past a
narrow band a "red" pack starts handing out oranges and stops being what the card
promised. The three neutrals override the defaults with near-zero saturation, so
their variation is entirely in brightness, which is what "shades of grey" means.

All ten cost the same. They're one product in ten flavours, and pricing one above
another would only be telling players their favourite colour is worth less.

### The cards show a real block

A flat icon can't show what a skin sells — the colour packs differ from each
other *only* by hue, and Neon only by material. So the shop and inventory tiles
render `BlockPreview`: an actual T-block spinning in a `ViewportFrame`. A pack
that pins a skin draws as that skin, transparency and texture included: Needoh's
card is glass, and Duck's is a textured duck block rather than the plain yellow
that would make it look like the sixty-coin Yellow pack.

Store owns the card and knows nothing about blocks. TowerGame hands it a renderer
through `Catalog.registerPackPreview(kind, render)`, from
`TowerSkinPresentation.client.luau` — a *client* file, because the renderer
returns a React element and a shared `Store.luau` loads on the server too. Any
other kind is unaffected and keeps its icon; a preview that errors falls back to
the icon rather than taking the shop down.

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
| Nuke | `3707809217` | action | `TowerService.nuke()` — the tower, not the round |
| Next Checkpoint | `3707809233` | action | `TowerService.clearStage()` |
| Extend Storm | `3708160736` | action | `TowerService.extendStorm(EXTEND_STORM_SECONDS)` |

The three bundles appear as cards in the shop's Robux tab. The actions never
appear in the shop — `group = "action"` keeps them out — because each has its
own button instead: Nuke and Skip are rail entries registered by
`TowerProductsPresentation` into the "actions" cluster (`assets.Icons.nuke` and
`assets.Icons.arrowRightOutline`), and Extend Storm is a button on the HUD
itself, beside the clock it buys.

### Extend Storm

`TowerService.extendStorm(seconds)` **adds** to `stormEndsAt` rather than
recomputing from now. That's what makes the purchase stack honestly: buying
twice buys two minutes, and buying early is worth exactly what buying late is.
Recomputing from now would quietly punish the second purchase and reward
panic-buying at zero. Like the other two it returns false during a checkpoint or
round break — both sequences set `stormEndsAt` themselves when they end, so time
added inside one is time thrown away, and a false leaves the receipt for
redelivery instead of eating it.

`TowerService.setStorm(seconds)` is its dev-only counterpart and the deliberate
opposite: it **replaces** the deadline, because the point of a console handle is
to land on a number without doing arithmetic against wherever the clock happens
to be. Nothing but the `setstorm` command calls it — the products go through
`extendStorm`. It raises `stormSeconds` when the new time is longer than the
stage was, since that's the denominator the HUD draws the storm bar against and a
fraction over 1 would draw the bar past its own end; it never lowers it, because
a shorter time left is exactly what a partly-drained bar looks like. Zero is
allowed and means "now".

### Nuke

`TowerService.nuke()` destroys **the tower, not the round**. It cuts every
standing block loose — out of `blocks`, out of `blockByModel`, and unanchored, so
the settled architecture becomes physics again — and detonates it where it
stands. Everything else carries on untouched: the checkpoint platforms stay, the
storm clock keeps counting, the stage target, the zone and the voted gamemode are
all exactly what they were, and the turn queue never stops. The holder even keeps
the piece they're aiming; it's just reseated down to the floor it used to clear
(`reseatHeldPiece(true)`), since the stack it was parked above is gone.

What the room loses is the climb above the last checkpoint floor, which is what a
nuke is supposed to cost them.

Taking the tower out of `blocks` **before** the blasts is load-bearing twice
over, and it's what `breakTower` and the checkpoint demolition already do: the
plane clamp only holds live blocks, so the wreck scatters in 3D instead of
sliding along the play plane; and the height poll stops measuring it, so a
settled block flung skyward can't be read as a taller tower and clear the stage
out of its own debris.

The barrage is `NUKE_BLASTS` (8) rungs walked up the tower, `NUKE_BLASTS_ACROSS`
(3) blasts abreast at each rung, spaced `NUKE_BLAST_INTERVAL` apart so they read
as a chain rather than a single frame in which everything vanishes. The rungs are
fired against the tower's own height, so the barrage covers what was actually
built — it climbs a tall stack and stays low on a short one — and the columns are
spread across `STEER_LIMIT_X` with `NUKE_BLAST_JITTER` of wander, so the whole
play plane goes up rather than one column of it. Each blast throws the wreck
rather than the (now empty) live list: `blastAt` takes an optional `targets`
list, which is the one thing the nuke needs that a bomb doesn't.

The wreck is swept `NUKE_WRECK_SECONDS` after the **last** blast rather than
after the purchase, so a piece can't be cleaned up out of a blast that was about
to throw it.

This deliberately isn't the round break. Routing the purchase through it made a
nuke worth less than it sounds: the room got a clean slate and a fresh gamemode
vote a moment later, so the tower it destroyed was one nobody had to rebuild.

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

### The chat announcement

All three action products announce themselves in chat — *"Someone bought
Nuke!"* — in the general channel, to everyone in the server. These are the
purchases the whole room feels (a tower gone, a stage skipped, a minute back on
everyone's clock), so the room is told who did it.

The announcement is **paired with the effect, not with the receipt**.
`TowerProductsService` wraps each handler in `announced(...)`, which sends only
after the handler returned true — so a purchase deferred for redelivery says
nothing until the retry lands, and no announcement can ever describe something
that didn't happen. Wrapping is the rule rather than three call sites remembering
to be polite.

The `Announce` packet carries **two ids and no text**:

| | |
| --- | --- |
| `productId` | Named from the shared Store catalog on the client, so renaming a product renames the announcement |
| `userId` | Resolved to a player on the client — a name resolved from a user id is one the buyer can't have made up |

The wording lives in `TowerAnnounceController.client.luau`, because chat is a
presentation and a sentence has no business on the wire. It writes through
`TextChannels.RBXGeneral:DisplaySystemMessage` (`Constants.ANNOUNCE_CHANNEL`),
colouring the buyer's name with `ANNOUNCE_NAME_COLOR`. Two things it refuses to
do rather than guess: on a place still running the **legacy chat** there is no
`TextChannels` and the announcement is simply skipped (the effect is already on
screen — missing chat is not an error worth a stack trace), and a buyer who left
between the purchase and the packet is dropped rather than announced with a hole
where the name goes. Names are escaped for rich text before interpolation —
display names can't contain markup *today*, and the escape is the difference
between "can't today" and "can't".

Nothing in the controller is nuke-specific beyond the packet, so a fourth action
product would need no edit there.

## Gamepasses

Also registered by `Store.luau`; ids live in `Constants.GAMEPASSES`. Ownership is
Roblox's answer, cached per session by Store and read on the **server** through
`StoreService.ownsGamepass` — never sent up by a client.

| Pass | Id | What it does |
| ---- | -- | ------------ |
| 2x Cash | `1949354348` | `CashService.award` pays `DOUBLE_CASH_MULTIPLIER` × the amount |
| Double Turn | `1951016323` | The owner takes `DOUBLE_TURN_TURNS` pieces each time the queue reaches them |

**2x Cash** hangs off `CashService.award` rather than off each award site, so
every way the game pays — zones, height, the clock, and anything a later feature
adds — doubles by one rule. Coins bought with Robux are a *purchase* rather than
earnings and are granted by `StoreService` at face value; they never come through
`award`.

**Double Turn** doesn't touch the queue. The owner is rotated to the back when
their first turn is handed out, exactly like anyone else, and the extra turns are
held in `repeatTurnFor` / `repeatTurnsLeft`, which `nextPlayer` reads before the
queue — so nobody else's place in the rotation moves. A player who leaves,
flips on "Not playing", or turns the perk off between the two loses the rest of
the run rather than stalling the queue.

**It can be put down.** A "Double Turn" toggle (`SETTING_DOUBLE_TURN`, on by
default) appears in Settings › Gameplay **only for owners**, and `nextPlayer`
reads it through `SettingsService.get` right beside the ownership check. Taking
two pieces every rotation isn't always wanted in a room of four friends, and a
perk you can't put down is a worse thing to have sold someone.

The row is registered in the shared `Settings.luau` like every other setting —
both realms have to agree the id exists or `SettingsService` rejects the write —
and *shown* conditionally from `TowerSettingsPresentation.client.luau`, which
calls `Settings.setVisibility` with a gamepass check and re-asks it on
`StoreController.GamepassesChanged` (ownership lands a moment after join). The
gate has to be client-side because ownership there is a `MarketplaceService`
call. See [Settings.md](Settings.md) § "Showing a setting conditionally"; note
that hiding a row is presentation, not permission — the server still validates
and re-reads the value, which is why `nextPlayer` checks it rather than trusting
the row to be absent.

The HUD says so while it's pending: `state.repeatUserId` carries whoever goes
again, and `TurnStrip` tags that chip **2x**. It's a tag rather than a second
entry in `order` because the strip keys its chips by user id — a duplicate id
would be the same chip, not a second slot — and because the order has to stay
honest about who is actually up next.

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
| `extendstorm` (alias `extend`) | `[seconds]` | `TowerService.extendStorm(seconds)` — replicates the Extend Storm purchase. Defaults to `EXTEND_STORM_SECONDS`. The only way to exercise that product without spending Robux, since its whole effect is a number on a clock |
| `setstorm` (alias `stormtime`) | `[seconds]` | `TowerService.setStorm(seconds)` — **sets** the time left on the stage clock rather than adding to it. Defaults to 10. `setstorm 0` lands the storm on the next tick, which is the only way to reach the wreck without waiting out a stage |
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

`TowerFeedbackController` calls `Sfx.preload()` (→ `audio.preloadCues`) once at
start, which pulls every Sound in the library — impact takes included — into that
client's cache. An unloaded one-shot plays *after* it downloads, i.e. after the
landing it belonged to, and a folder of takes is a folder of separate assets each
with its own first play to get wrong.

Cues are cloned from `Assets.Sounds` rather than referencing raw asset ids, so
re-tuning a cue's volume or pitch is a Studio edit and not a code change. A
missing sound warns once and is otherwise a no-op — audio going quiet should
never take gameplay down with it.

That loading, cloning and cleanup now lives in the **framework**
(`Boil.audio.playCue` / `playCueAt` / `playCueAtPosition`), since a Studio sound
library isn't a TowerGame idea and GamemodeVote wanted one too — it couldn't
reach this file without a cycle, because TowerGame registers *into* GamemodeVote.
`Sfx.luau` survives as a ~20-line binding for one reason: every TowerGame cue
carries the same falloff (`SOUND_RANGE`), and threading that through a dozen call
sites would repeat a decision that belongs in one place. Call sites are
unchanged.

Music is **one track per zone**: a zone is the game's chapter, so it's the thing
worth scoring. The track loops until the zone changes rather than handing off
partway through, and the playlist is shuffled (and reshuffled once exhausted) so
a long session doesn't repeat in a fixed order. Client-side, so each player
drives their own. Boil's own Music feature is switched off
(`Music/Constants.ENABLED`) so the two don't fight over the mix.

Gated on the **`tower.music`** toggle, registered under Audio in this feature's
`Settings.luau`. TowerGame owns that row rather than reading Music's
`music.enabled`: naming another feature's setting id breaks when that feature is
uninstalled, and the two constants would drift silently in the meantime. Music
registers its row only while its own controller is live, so the player sees
exactly one "Music" switch whichever combination is installed.

Switching music off destroys the playing clone but keeps the *template* loaded,
and zone changes keep advancing the playlist silently. So toggling doesn't burn
through the shuffle, and switching back on gives you the track for the zone
you're actually in rather than resuming one from three checkpoints ago.

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

**The overview toggle** (the HUD's magnifier, bottom right) frames the current
tower: `zoneBaseHeight` — the floor the run is standing on — up to `height`, plus
`CAMERA_OVERVIEW_PADDING`. It measures from the current floor rather than from the
base because everything below that floor has been demolished (see [the checkpoint
platform](#the-storm)); framing from the base would spend most of the shot on the
empty column where old stages used to be and squeeze the tower into a sliver at
the top. On the first stage the two are the same thing. Its height minimum is a
span *above the floor*, not an absolute altitude — `height` is measured from the
base, so by floor five it's already hundreds of studs and a floor on `height`
would never bite. The toggle is a **preference, not an override**: `target` checks
phase first, so an overview left switched on can't eat the checkpoint cutscene's
shot or the round break's.

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
count zeroed, gap back to 40, and the clock back to its un-grown 300.

One thing deliberately survives: **`maxHeight`**. It's the server's best-ever
record rather than part of the run, and `TowerStatsService` has already banked it
into each player's profile. The HUD's "best" is a record; the storm resets the
game, not the history.

### The opening vote

**A session's first round is voted for like every other one.** `runOpeningVote`
runs from `TowerService.Start`: `intermission` goes up immediately, so the game is
parked before it has dealt anything, and the ballot opens as soon as there is
somebody to vote. Then it's the same `settleOnAMode` the round break uses, followed
by a fresh storm clock and `PHASE.SETTLING`.

It **waits for a player** (`#queue > 0`) plus `OPENING_VOTE_DELAY` (2.5s) for their
client to mount its UI. Both waits earn their keep: a poll against an empty server
is fifteen seconds of nothing followed by the default — the exact un-voted round
this exists to stop handing out — and a ballot that opens behind a loading screen
spends its own clock there. There's no wreck, no `resetRun` and no
`reportRoundLost`, because there is no round behind this one.

### The round break

The storm landing ends the **round**, and `runRoundBreak` owns everything between
that and the next one. It is the only moment a *running* game is stopped:

1. `intermission` goes true and `PHASE.GAMEOVER` goes out. That flag is what makes
   "paused" real rather than cosmetic — the turn queue parks, the height poll
   returns early (which is also what freezes the storm clock), and no piece can be
   held, so **nothing can be placed** for the duration.
2. The wreck flies for `ROUND_BREAK_WRECK_SECONDS` (3). Clients read `GAMEOVER` and
   play `StormFade` — a one-shot white-out that waits
   `STORM_FADE_DELAY_SECONDS` (so the blocks are seen flying *first*), fades to
   white, holds, and clears.
3. **The players vote on how the next round plays** (see
   [the gamemode vote](#the-gamemode-vote)), through the same `settleOnAMode` the
   opening vote uses. It yields here — for the poll, and for a whole match each
   time PVP wins.
4. The winning modifier is applied, the storm clock is set fresh — so no part of
   the new round is spent on the poll — and `ROUND_BREAK_RESUME_SECONDS` later the
   queue starts again.

`TowerService.nuke()` does **not** route through this — a nuke takes the tower
and leaves the round alone. See [Nuke](#nuke).

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
- **Most block types haven't been watched in a real run.** All fifteen are wired
  end-to-end, but the odds curve is deliberately stingy (3% on the first
  floor), so forcing one means the `block` Cmdr command (`block Ghost`,
  `block Magnet` — it matches on the type's name), raising
  `BlockTypes.BASE_CHANCE`, or zeroing every other type's `weight`. Ghost's
  collision-group rule has been verified directly — a ghost-grouped part dropped
  from above a twenty-block tower passed through all of it and came to rest on the
  base. **Magnet has been played twice and reported invisible both times**, which
  is what the third tuning (a per-frame velocity field, not an impulse — see the
  Magnet note) is answering. Whether the field now gathers a lean without imploding
  a good stack is the next thing to watch; it has not been played yet. **Sacrifice
  has never been played at all** — the ray geometry is the part to check, in
  particular a piece landing across two towers and a piece landing on the base.
  **Crate is benched** while its loose-cell behaviour goes unwatched. The rest
  (Anvil, Ice, Anchor, Mystery, Feather) have had no play-testing at all —
  in particular `ANVIL_PHYSICS`'s density and `FEATHER_FALL_SPEED` are first
  guesses, and a Feather's drift is slow enough that it may want its own turn
  clock.
- **Name plates disappear on settle**, so there's no way to tell a Glue block from
  an ordinary one once it's part of the tower. That's the intended trade — fifty
  plates is a wall of text — but if a type ever needs to be readable *in* the
  tower, `BlockLabel.dismiss` is the one call to reconsider.
- **Skins are colour and material only.** Making a block actually *look* like a
  Needoh means squash-and-stretch on impact, which is a deformation problem the
  cube geometry doesn't allow. The sound carries it for now.
