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

- Each stage names a `targetHeight` and a `STORM_SECONDS` (300) clock. The first
  checkpoint is `STORM_FIRST_TARGET` (40 studs) up, and every cleared stage puts
  the next one `STORM_GAP_GROWTH` (8) studs further than the last gap — 40, 48,
  56, and so on.

  **Read the target against the turn budget, not on its own.** A stage is one
  shared allowance of about eighteen turns (`STORM_SECONDS` / (`TURN_SECONDS` +
  `SETTLE_SECONDS`)) however many players are in the room, and a flat piece adds
  `BLOCK_SIZE` (4) studs. The first target used to be 60 — fifteen of those
  eighteen turns spent gaining full height, a three-turn margin for every piece
  that slid off and every player who wasn't looking — and the onboarding funnel
  lost three quarters of its players at the first checkpoint. 40 is ten clean
  placements. The growth was raised alongside it so only the early stages get
  easier: the curve passes the old one by the fifth checkpoint.
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
physics but still count toward the tower's top.

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

  `TowerAfkView` adds the **GUI inset** back before positioning it, converted
  into canvas units by dividing by the viewport scale. The root ScreenGui sets
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

**Only the newest platform survives.** When a floor lands, every earlier one goes
out with the scaffolding under it: `blastPlatformsBelow` un-anchors them, turns
off their collision and queries (so a tumbling slab can't shove a surviving block
or swallow the landing preview's raycast on its way past), shoves them with the
same blast the blocks get, and destroys them a second later. A platform is the
ground only until the next one lands above it; after that it's a slab in dead air
that nothing can reach, and leaving the stack standing meant the overview shot
framed the whole dead column instead of the tower being built.

They come out of the `platforms` list *before* they're shoved, for the same
reason `blastBlocksBelow` empties its list first — that list feeds `restingTopY`,
and a slab thrown upward by the blast would otherwise read as the top of the
tower and fire the next piece's spawn into orbit.

The **base is not a platform** and is never demolished: it's where the run
restarts after the storm, and in a Studio-built place it's the user's own tagged
part rather than something the service made. It just ends up permanently out of
frame, since every shot is now measured from the current floor.

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
| Roulette | **70%** of pieces are special — a flat `blockTypeChance` that bypasses the curve *and* `MAX_CHANCE`. |
| Lightning Storm | Lightning strikes in **every** zone, not just Stormy. |

**Classic is always on the ballot** — it carries `pinned = true`, so GamemodeVote
keeps it and rolls the remaining slots from the twists. A ballot of nothing but
twists gives the players no way to decline one; Classic is that answer. It also
sits first (`order = 0`, and nothing else claims it), so it's the one panel you
can pick without reading. Its modifier *is* `Gamemodes.DEFAULT` — winning Classic
and skipping the vote have to produce the same round, or one of them is lying.

A ballot is **three panels** (`BALLOT_SIZE`): Classic plus two of the twists,
re-rolled every vote. Registering a fifth mode makes the ballot more varied, not
wider.

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
| **Burning** | Burns blocks, careful! | Arrives alight; chars black over `BURN_SECONDS` (20) and disintegrates, spreading to whatever it touches — up to `BURN_MAX_SPREAD` (3) other blocks per fire. |
| **Noob** | Places a Noob. | Replaces the tetromino with a Noob that walks and jumps until something lands on it. |
| **Anvil** | Heavy! | Ten times the density (`ANVIL_PHYSICS`). Ploughs through what it lands on, immovable afterwards. |
| **Ice** | Nothing sticks. | `ICE_PHYSICS` — friction taken out, high `frictionWeight` kept so the ice wins the contact and things slide *on* it. |
| **Anchor** | Locks itself in place. | Anchors every one of its parts on settle. Holds itself, welds nothing. |
| **Mystery** | ??? | Lands as a question mark, then rolls one of the landing types and fires it. |
| **Crate** | Breaks apart! | Cuts its own welds on settle and collapses into the loose cubes it was pretending to be. |
| **Feather** | Takes its time. | Terminal velocity of `FEATHER_FALL_SPEED` (12 studs/s) on the way down, and light enough to shove nothing. |
| **Ghost** | Falls through the tower. | Phases through every block for `GHOST_SECONDS` (1.2) after release, then turns solid wherever it got to. Still lands on the base and the platforms. |
| **Magnet** | Pulls blocks in. | On settle, tugs every loose block within `MAGNET_RADIUS` toward itself — `blastAt` pointed the other way. |

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
- **Crate** breaks on **settle**, like Glue and Clone, and for the same reason —
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
  at the cost of the same seconds off their turn clock.
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
- **Magnet** is `blastAt` with the sign flipped, sharing its distance falloff and
  its mass scaling, and departing in one place: **no upward bias**. A blast lifts
  because an erupting tower reads better than a swept one, but a pull that lifted
  would hand the room free height for landing a single piece — and height is what
  the whole game is scored on. It's much weaker and tighter than a Bomb (22/26 vs
  46/120) because a pull as strong as the blast doesn't gather a tower, it
  collapses one inward, which is just a slower bomb. Anchored blocks and the
  platforms ignore impulses on their own, so it can't drag the floor out.
- **Mystery** is a bluff: you place it exactly as carefully as you'd place the
  worst thing it could be. It rolls from the types flagged `viaMystery` — Bomb,
  Glue, Clone, Burning, Anchor, Crate, Magnet — weighted by the same `weight` the ordinary
  roll uses, so a type that's rare as a piece stays rare as a reveal. The physics
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
  out of `LocalTransparencyModifier`'s reach).

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
| Later checkpoints | +48, +56, +64 … above the last one; everything below each new floor is demolished | `STORM_GAP_GROWTH` |
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
exists at any moment is *one stage's climb* (`stormGap`, 60 studs and growing by
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
| `Zones.luau` | shared | The seven zones, their skies, and their gravity |
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
| `TowerAfkPresentation.client.luau` | client | Registers the card as an always-mounted root (`Presentations.afk`) |
| `AfkNotice.ui.luau` | shared | Dumb card: the copy, the red / green pair, the screen cover |
| `SpectatorNotice.ui.luau` | shared | The badge that stays up while a player is out of the rotation |
| `TowerHUD.ui.luau` | shared | Dumb HUD (turn strip, height, clocks, hint, touch controls, Extend Storm, the urgency tick) |
| `TurnStrip.ui.luau` | shared | Headshot row, current player centered |
| `ControlsHint.ui.luau` | shared | Bottom-left control list that fades out |
| `StormFade.ui.luau` | shared | The storm's one-shot white-out, played on `PHASE.GAMEOVER` |
| `SteerStick.ui.luau` | shared | Touch steering: a horizontal drag track reporting analog `[-1, 1]` |
| `SteerStick.story.luau` | shared | UI Labs story — drag it with the mouse, with a live value readout |
| `TowerHUD.story.luau` | shared | UI Labs story — every prop on a slider, including both clocks |
| `StormFade.story.luau` | shared | UI Labs story — replays the white-out on demand |
| `TowerPresentation.client.luau` | client | Registers the HUD as a UIRegistry **root** |

## The HUD

```
                 ( o ) (O) ( o )           turn strip — current player centered
          (⚡) [ 24.5 studs  best 60.0 ] (◕) Extend Storm | height | turn clock
              ●────────●────────────○      progress: start, tower, next zone
                   3:42 until storm!
  Move — A / D…        Your turn — Bomb T-Shape       [LEFT][TURN][RIGHT][DROP]
  (fades after 60s)                            $ 1,250   (touch only)
```

The **turn clock is a plain circle** (`RadialTimer`), only existing while
someone is aiming. Two radial-fill treatments were tried first — a filling pie
and a hollow ring, both built from `UIGradient` hacks to fake a radial sweep
since Roblox has no native one — and neither read well in practice, so the dial
is a solid circle with the seconds label on top; its colour still shifts red
under `URGENT_SECONDS`.

### Nothing that comes and goes may move what stays

The dial and the Extend Storm button **flank** the stats row at `FLANK_Y`,
positioned absolutely *outside* the column rather than laid out inside it.

This is the fix for a real bug, not a style choice. The dial used to sit in a
row beside the stats panel, so the panel had to give up width for it — which
meant the height readout resized *and* slid sideways twice a turn, every turn.
Worse, mid-tween the row was briefly wider than the column and centred itself,
shoving the panel a further half-dial to the left. Now the panel is a fixed full
width and the dial simply appears in a gap that was always there. Measured live:
the panel's x and width each hold a single value across turn boundaries.

The dial **pops in** on mount — a `UIScale` tweened 0 → 1 on `Back/Out`, so it
reads as arriving rather than fading up. Its appearance is the cue that a turn
started, which is worth animating.

The last `URGENT_SECONDS` (5) of a turn **tick audibly** (`audio.playUI("tick")`).
Keyed on the whole second rather than the raw countdown, and latched so a
re-render inside the same second can't double it up; the latch clears whenever
the countdown leaves the window, which re-arms it for the next turn without
having to watch the turn itself.

The **progress line** (`ProgressLine`) measures *this leg of the climb only* —
from `zoneBaseHeight` (where the current zone started) to `targetHeight` — so a
run always begins at the left dot no matter how tall the tower already is. The
tower is a dot for now; it's a separate element rather than a bar fill precisely
so it can grow into a little stack later.

**The whole storm row is dropped during `PHASE.GAMEOVER.`** The round is over,
the tower it measured is wreckage, and the server has frozen `stormEndsAt` — but
the client draws the clock as `stormEndsAt - now`, so leaving it up counted a
dead deadline down behind the gamemode vote and then snapped back when the next
round started. It stays up through a checkpoint, where the line showing the leg
just built is the point of the moment.

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
| `IDLE_TURN_SECONDS`, `IDLE_GRACE_TURNS`, `IDLE_TURNS_BEFORE_AFK` | The short clock for an untouched turn (6), how many of a player's first turns are exempt (1), and how many untouched turns in a row bench them (2) — see [Idle turns](#idle-turns-and-the-inactivity-card) |
| `EDGE_MARGIN` | How far anything pinned to a screen edge sits in from it (20). Shared by the HUD and the spectator badge so the two can't disagree |
| `SPECTATOR_NOTICE_WIDTH`, `SPECTATOR_NOTICE_TOP`, `SPECTATOR_NOTICE_COLOR` | The spectator badge. `TOP` hangs it below the HUD's top column; the GUI inset is added on top of it at render |
| `SETTLE_SECONDS` | Pause between turns |
| `STEER_SPEED`, `STEER_LIMIT_X` | How fast a piece slides and how far off-center it can get |
| `GAMEPAD_STEER_DEADZONE` | Below this the left stick reads as centred and the D-pad / bumpers take over (0.2) |
| `SPAWN_CLEARANCE` | Clear air under a fresh piece, measured from its lowest possible point — see [The held piece](#the-held-piece) |
| `STORM_SECONDS` | The stage clock (300) |
| `STORM_FIRST_TARGET`, `STORM_GAP_GROWTH` | First checkpoint at 40 studs, each next gap 8 further. Tune them against the ~18-turn stage budget, not on their own — see [The storm](#the-storm) |
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
| `CRATE_SCATTER`, `CRATE_LIFT`, `CRATE_SPIN` | How far a broken Crate's cells throw themselves apart. In-plane only |
| `GHOST_SECONDS`, `GHOST_TRANSPARENCY` | How long a Ghost phases for, and how see-through it is while it does |
| `BLOCK_COLLISION_GROUP`, `GHOST_COLLISION_GROUP` | The two groups that let a Ghost ignore blocks without ignoring the floor |
| `MAGNET_RADIUS`, `MAGNET_IMPULSE` | Reach and strength of a Magnet's pull. Read them against `EXPLOSION_RADIUS` / `EXPLOSION_IMPULSE` — same mechanism, opposite sign |
| `MYSTERY_REVEAL_SECONDS` | How long the revealed name hangs over a Mystery block |
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
| Stormy | struck blocks are destroyed | rain, plus **lightning** that detonates where it lands |
| Space | unchanged | `workspace.Gravity` drops to **30** |
| Foggy | unchanged | `Lighting` fog closes in to `FOG_END` |
| Night | each gains a `PointLight` in its own colour | dark: `Brightness`, `Ambient` and `ClockTime` drop |

Only special zones announce themselves — a normal zone is just a new sky. The
banner clears itself after `ZONE_WARNING_SECONDS`.

### The cadence

Zones arrive on a **rhythm, not a roll**: `Zones.next` returns a normal zone
unless `(cleared + 1)` is divisible by `NORMALS_PER_SPECIAL + 1`, which puts a
special every third zone — two calm floors, then a twist.

A weighted roll (what this replaced) can hand out four specials in a row or none
for six floors, and neither is the shape of a run anyone wants. *Which* special
comes up is still random, and `avoidId` stops the same one landing twice running.

Normal zones therefore never roll, so their `weight` is unread — it's kept only
so every row of the table reads the same.

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
46): a bomb is a piece the players were handed and can plan around, while this
arrives unasked.

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
names no gravity and gets `Zones.DEFAULT_GRAVITY` (196.2) back. `resetRun` and
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

### Spending it

Cash is registered with the [Store](Store.md) as the **`coins`** currency, whose
balance lives at `{ "TowerGame", "Cash" }`. Store is told the *path* rather than
given a copy, so there's still one source of truth — `CashService` is the only
thing that pays out, and `StoreService` is the only thing that debits.

## Skin packs

`SkinPacks.luau` lists the buyable block looks, in two families:

| Pack | Price | Effect |
| ---- | ----- | ------ |
| `skins.needoh` — Needoh Blocks | **not for sale** | Every block **is** the Needoh `BlockSkin` — glass, translucent, squish on every landing |
| `skins.neon` — Neon Blocks | 100 coins | Every block part becomes `Enum.Material.Neon` |
| `skins.red` … `skins.black` (10) | 60 coins | Every block you place is a **random shade** of that colour |

A skin pack overrides the look of **the blocks its owner drops**. A pack that
owns the surface (Neon, Needoh) also overrides whatever the current zone had
dressed them in — a Retro zone can't dull a neon block or stud a Needoh one.
That override is the product; `SkinPacks.ownsSurface` is the one place that
decides which packs get it.

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
that pins a skin draws as that skin, transparency included: Needoh's card is
glass, or the tile would advertise a solid block.

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
- **The block types haven't been watched in a real run either.** All fourteen are
  wired end-to-end, but the odds curve is deliberately stingy (3% on the first
  floor), so forcing one means the `block` Cmdr command (`block Ghost`,
  `block Magnet` — it matches on the type's name), raising
  `BlockTypes.BASE_CHANCE`, or zeroing every other type's `weight`. Ghost's
  collision-group rule has been verified directly — a ghost-grouped part dropped
  from above a twenty-block tower passed through all of it and came to rest on the
  base — but neither Ghost nor Magnet has been seen as a *dealt piece*. Magnet's
  pull strength in particular is a first guess. The six before them
  (Anvil, Ice, Anchor, Mystery, Crate, Feather) have had no play-testing at all —
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
