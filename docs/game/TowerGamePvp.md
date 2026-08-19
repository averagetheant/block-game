# PVP

The every-player-for-themselves round. Six lanes, six platforms, no turns: every
player holds their own piece at the same time as everyone else and builds as high
as they can before one shared clock runs out. Whoever's tower is tallest when it
stops wins, and the standings go up over the towers they belong to.

It's a **gamemode**, not a separate place — it wins the ordinary
[GamemodeVote](GamemodeVote.md) ballot and replaces the round that would have
followed. Vote it twice and you play it twice.

Prototype status: built end to end and **play-tested solo only** — a full match
with one lane. Two towers on the board at once has never been run. See
[Not built yet](#not-built-yet) for what's knowingly missing.

## How a round becomes a match

`TowerService.runRoundBreak` is the seam, and it's a three-line one:

```
wreck → vote → while stage.pvp do PvpService.runMatch(); vote again end → classic round
```

The vote returns `pvp`, whose modifier carries `pvp = true`
([Gamemodes.luau](../../src/features/TowerGame/Gamemodes.luau)). The round break
hands the board to `PvpService.runMatch`, which **yields for the whole match**,
and then puts the ballot back up rather than dropping the room into a classic run
nobody picked. Everything outside that loop — the wreck, the reset, the fresh
storm clock, the round funnel — happens once, for whichever mode the players
finally settle on.

`intermission` stays true for the whole match, which is what makes "PVP owns the
board" real rather than cosmetic: the classic turn queue parks, the storm clock
freezes, and the classic `State` packet stops being broadcast.

**Freezing it means holding it, not ignoring it.** `stormEndsAt` is an absolute
server time and the HUD draws the bar as the distance from now to it, so a clock
nothing reads still drains on screen. The poll calls `holdStormClock()` from both
of its parked branches — the `pvpActive` one and the `checkpointActive or
intermission` one — which pushes the deadline out a full stage every tick. Without
it, three minutes of PVP plus the ballot after it left the next classic round's
bar sitting at about a minute before its first turn.

**The zone goes back to clear skies when the match ends.** A match rolls its own
zones through `applyZone`, which writes the classic world state directly, so
`settleOnAMode` calls `restoreDefaultZone()` next to `setBaseOnBoard(true)` — the
same "PVP borrowed this, put it back" pair, and outside the `pcall` for the same
reason. The ballot after a match runs under clear skies, and a classic round no
longer opens in whatever zone the match happened to end in.

## The lanes

| | |
| --- | --- |
| Seats | `PvpConstants.MAX_LANES` (6), fixed — slot 2 is in the same place whether three players are in or six |
| Spacing | `LANE_SPACING` (120 studs) between centre lines |
| World X | `PvpLanes.xOf(slot)` = `(slot − 2.5) × 120`, so the board is centred on the arena origin: −300 … +300 |
| Platform | The same `PLATFORM_SIZE` slab the classic base and every checkpoint uses, at `LANE_Y` (the classic base's altitude) |
| Parent | `workspace.TowerArena.PvpLanes` |

**The spacing is a safety rule, not a look.** A tower is about 52 studs wide
(`STEER_LIMIT_X` ± half a block), and a bomb throws everything within
`EXPLOSION_RADIUS` (36) of itself. 120 leaves ~68 studs of air between two towers,
which is more than a blast on the near edge of one lane can reach into the next.
**Nobody may wreck a neighbour's tower** — that is the whole reason lanes are this
far apart rather than merely not overlapping, and it's the single assumption the
next section rests on.

`PvpLanes.luau` is the only place a slot becomes a position. Only the slot travels
on the wire, so a second copy of that arithmetic would be a client whose camera
looks a hundred studs to the left of the tower it's meant to be watching.

## Why there's still only one bomb in the codebase

PVP owns the match: lanes, who's in one, the clock, the zone, the standings. It
owns **none of what a block does**. Pieces are built, dropped, settled, burnt,
blasted, welded, ignited and held to the play plane by TowerService's block
engine, which `PvpService` drives one lane at a time.

That was possible because **every hazard in the game is already spatial**. A bomb
has a radius. A fire spreads by contact. Glue welds what it's touching. A magnet
pulls what's near. The plane clamp only ever looks at Z. None of them ask which
tower they're in, so a second tower two hundred studs away needs no new rule to be
safe from the first — it just needs to be far enough away, which is what
`LANE_SPACING` guarantees.

So `Block.laneX` exists, and it is **only ever read to measure**:

| Reads `laneX` | Doesn't |
| --- | --- |
| `restingTopY` — what a piece may spawn clear of | Bombs, fires, glue, clones, magnets, ghosts, anchors, crates |
| `measureLane` — the scoring height | `clampToPlane` |
| `laneBlockCount`, `clearLane` | The settle detector, the burn tick, the despawn sweep |

The block engine's public surface, all of it on `TowerService`:

| Call | Does |
| ---- | ---- |
| `dealPiece(player, laneX, floorY)` | Roll a piece, build it, dress it for the zone, park it clear of that lane, mark it theirs. Returns the `Held`. |
| `dropPiece(player)` | Hand their piece to physics. Returns the `Block`. |
| `cancelPiece(player)` | Take it back **without** dropping it. |
| `applyPlacement(player, x, turns)` | Clamp and apply, `x` measured from their lane centre. |
| `reseatFor(player, down?)` | Lift the piece if the lane grew under it. |
| `laneHeight(laneX, floorY)` | The scoring height of one lane. |
| `laneBlockCount(laneX)` | How many blocks are standing in it. |
| `clearLane(laneX)` | Destroy the lane's piece and every block in it. |
| `applyZone(zoneId, sky)` | Make a zone true in the world without touching the classic packet. |
| `isSpectating(player)` | The "Not playing" answer, including the solo carve-out. |

The classic game calls the same functions through thin wrappers: `beginTurn` is
`dealPiece(player, CLASSIC_LANE, baseTopY)` plus the turn clock and the funnel,
and `release` is `dropPiece` plus who gets paid.

### The one thing that had to change shape

`held` was a single slot and is now `heldBy: { [Player]: Held }`. Classic deals one
piece at a time so it holds at most one entry, and `turnHolder` names whose piece
the turn loop is waiting on. Keying by player is what let the whole held-piece
lifecycle stay one implementation — and it cost nothing on the client, because
the attribute a client finds its own piece by (`HELD_ATTRIBUTE`) was **already**
keyed by user id.

## The match

| Phase | Length | What's happening |
| ----- | ------ | ---------------- |
| `COUNTDOWN` | `COUNTDOWN_SECONDS` (5) | Lanes are standing, nobody has a piece. Look at who you're up against. |
| `PLAYING` | `MATCH_SECONDS` (180) | Every lane deals itself pieces on its own clock. |
| — the freeze | `FREEZE_SECONDS` (2) | Still `PLAYING` on the wire. Pieces in the air are taken back, nothing new is dealt, heights stay live. |
| `RESULTS` | `RESULTS_SECONDS` (12) | Heights are final, standings go over the towers, rewards are paid. |

**The freeze isn't cosmetic.** A piece dropped in the final second is still
falling when the clock stops, and it counts if it comes to rest on the tower — so
the heights have to stay live for a beat after the clock. They're frozen at the
*end* of it, before anything is drawn or paid, which is what makes the board on
screen and the board the rewards were paid against one set of numbers.

Pieces still being aimed when time runs out are **cancelled, not dropped**
(`TowerService.cancelPiece`). A block released after the clock is a block that
could still be climbing while the standings are being read, which would let the
last moment of a round decide it.

Seats are handed out **before** the countdown, so the camera has a lane to land on
rather than drifting onto one five seconds in.

**One poll drives all six lanes**, at `Constants.POLL_INTERVAL`. A coroutine per
lane would be no cheaper and would give the match six places where time passes —
so "the clock stopped" and "stop dealing pieces" could land in different orders on
different lanes.

Each poll, per lane: measure it, reseat the held piece (upward only, same rule as
classic), and hand out the next piece if one is due.

**The gap is started by the poll, not by the drop.** The first poll that finds a
lane empty books the next piece for `PIECE_GAP_SECONDS` (0.5) later. Doing it that
way is what makes pressing DROP and the clock running out feel identical — neither
path has to remember to book the next piece, and neither can book it twice.

`PIECE_SECONDS` (20) is longer than a classic turn (15) on purpose: nobody is
waiting on you, so the clock exists only to stop a piece hanging over a tower
forever.

**Special blocks ramp from 20% to 30%** over the match.
`PvpConstants.specialChanceAt(progress)` is linear from `SPECIAL_CHANCE_START`
(0.2) to `SPECIAL_CHANCE_END` (0.3), reaching the top at `SPECIAL_CHANCE_FULL_AT`
(0.85 of `MATCH_SECONDS`), so the last ~27 seconds run flat at 30%.

Rising rather than flat because the mode's shape is rising — the towers that win
are tall by the last minute, and a hazard costs more the taller the thing it lands
on. The ramp stops short of the whistle on purpose: a rate that only arrived at
time would be delivered to nobody.

It rides the same `blockTypeChance` lever Roulette uses, which bypasses the
escalating curve *and* `BlockTypes.MAX_CHANCE` (0.4). The curve is a function of
checkpoints cleared, and a PVP match clears none, so it would sit at its 3% floor
for the whole three minutes.

**The rate is read per piece, in `dealTo`, not once at the whistle** — that is what
makes it a ramp rather than a constant chosen at the start. `matchProgress()`
reads 0 outside `PLAYING`, because `endsAt` belongs to the countdown or the
results panel then. The number goes to `TowerService.dealPiece`'s `chance`
argument, which outranks `stage.blockTypeChance` and is itself outranked by the
`blockrate` console knob. The `pvp` gamemode's `blockTypeChance` is left at the
opening 20% as the fallback for a piece dealt outside a live match.

**Lane platforms are floors, not blocks** — `Constants.FLOOR_PHYSICS`, the same as
the classic base. With `BLOCK_PHYSICS` they lost their own contacts to the physics
types' weights, so a Bouncy piece bounced off the bare platform and an Ice one slid
across it. PVP is where that showed up: a lane starts empty and stays short, so far
more pieces land on bare platform here than ever land on the classic base. See
[TowerGame.md](TowerGame.md#block-types) for the arithmetic.

Pieces come from one shared bag (`nextShape` on the server), so all six lanes draw
from the same sequence. Invisible today because there's no next-piece preview; if
one is ever added, this needs to become per-lane.

## Joining, leaving, and sitting out

The three rules the mode is fussy about, and why:

**A player who joins mid-match gets a lane** the next poll, if a seat is free.
Handled by `admitWaiting`, which asks "is anyone here without a lane who wants
one?" every poll rather than binding `PlayerAdded` — because that's the same
question as the next rule and they should be one answer.

**Turning "Not playing" back off mid-match gets you a lane too**, through that
same sweep. So the way in is one path whether you arrived late or changed your
mind.

**Turning "Not playing" back on mid-match does nothing at all.** The lane stays,
the tower stays, and the pieces keep coming. This is deliberate and it's the
anti-exploit: if the tower despawned, a player could spam the toggle to re-roll a
fresh platform whenever their stack went wrong. Doing nothing is the least
complicated answer, and it doesn't reward the fiddling. The setting is therefore
read **only when a lane is granted**.

**A player who leaves takes their tower with them.** Their lane is retired and
`clearLane` destroys what was in it — otherwise it would stand there being
measured for somebody who can't see it, and the seat should go to whoever comes
through the door next.

**Six is a place setting as well as a constant.** `Players.MaxPlayers` can't be
written at runtime, so set the server cap to 6 in Game Settings. `MAX_LANES` caps
the seats regardless; a seventh player simply finds none free.

## The zones

The classic run changes zone when a checkpoint is cleared. PVP clears none, so the
zone is on a clock: a fresh one every `ZONE_SECONDS` (35), about five over a match.

`Zones.roll(avoidId)` is the PVP counterpart to `Zones.next` — a plain weighted
roll over the **whole** list, avoiding the one that's up. The cadence
(two normals, then a special) is measured in checkpoints and has nothing to count
here, and a run of two calm zones would be most of a three-minute round. The
weights already say a normal zone should come up about three times as often as any
one special, which is the shape this wants. Incidentally this is the first thing
to *read* the normal zone's weight, which `Zones.luau` had been carrying unused.

The first zone of a match is always the plain one (`FIRST_ZONE_NORMAL`), so the
first thirty seconds are spent learning the mode rather than the weather.

### The roll window, and the reel

A zone is **announced before it is true**. `rollZone` picks the next one, puts it
on the wire immediately, and defers the part that changes the world by
`ZONE_ROLL_SECONDS` (2) — the packet carries `zoneAt`, the server-time stamp of
the moment it lands, the same way `endsAt` carries a clock.

Both realms hold off to that stamp. The server delays `TowerService.applyZone`
(gravity, snow friction, retro studs); `TowerZoneController` delays the visual
half (sky, weather, fog, block lights, the `ZoneReached` cue). A stamp rather than
a local countdown is what makes the sky change at the same instant on a good
connection and a bad one.

The window is what `ZoneReel` spends spinning. The zone line in the HUD's top
column flicks through the zone names, easing out as it goes, and stops on the one
that actually rolled at the instant the world takes it — then puts up a card
saying what that zone *does* (its `warning`, the same line the classic banner
shows) for five seconds before
settling back to a plain muted label.

Two things fall out of doing it this way rather than animating on arrival:

- **The reveal isn't spoiled.** A sky that changed while the reel was still
  turning would answer the question the reel is asking.
- **Nothing moves under a piece without notice.** Space dropping gravity to a
  sixth mid-aim is the change most worth two seconds of warning, and the reel is
  that warning.

The answer *is* on the wire for the whole window, and that's fine: nothing in the
world has changed yet, so a client that read ahead would only be spoiling its own
surprise. The first zone of a match skips the window entirely (it arrives with the
world during the countdown — nothing to reveal, no tower to disturb), and a match
that ends mid-roll retires the pending apply on both realms rather than dropping
the next classic round into somebody else's weather.

**The line is the same one the classic HUD banners** — `zone.warning`, read
straight off the zone by both surfaces. There is exactly one string per zone: the
longer `description` field is gone, and with it any way for a zone to say one
thing in a classic round and another in a match. To reword a zone, edit its
`warning` in `Zones.luau` and both modes follow. The reel holds it for
`DETAIL_SECONDS` (10, in `ZoneReel.ui.luau`) against the classic banner's
`Constants.ZONE_WARNING_SECONDS` (4.5) — the reel is the only place a match
explains a zone, so it stays up longer than a banner a player will see again next
round.

**Clear Skies has a line now too**, because the reel lands on it as often as on
anything else and "nothing is out to get you" is an answer worth printing. That
used to be what `description` was for. Whether a zone *announces itself* — the
classic banner and its sound — is asked of `Zones.announces(zone)` (`kind ~=
"normal"`) rather than of whether it has copy, so a zone can have a line without
the classic run banging a drum about clear weather every third checkpoint.

**Stormy's line used to be the caveat here**, because it names lightning that a
match didn't have. It has one now — see [The storm](#the-storm) — so the same
string is true in both modes, which is the outcome one shared line was betting on.
If a zone ever does genuinely differ between the modes, a per-mode override goes
back behind a function on `Zones`; one zone would not have earned it.

Everything a zone does still applies: gravity (Space), snow friction, Retro studs,
the fog, Night's per-block lights, the sky. The server calls
`TowerService.applyZone`, which dresses every standing block and every held piece
and writes `workspace.Gravity` — but deliberately does **not** touch the classic
state packet, which is stale for the whole match. The zone rides the PVP packet
instead, and `TowerZoneController` reads whichever packet is live.

**Weather follows your own lane.** `followTower` positions the rain/snow emitter
over `PvpLanes.xOf(myLane.slot)` at your own tower's height — snow falling over the
middle of a six-lane board would be weather nobody is standing in.

**Lightning strikes every lane at once** — see [The storm](#the-storm).

## The storm

Stormy behaves in a match the way it does in a classic round: a red column stands
where the next bolt will land, and a few seconds later it lands. The difference is
that there are six of them.

**One clock for the whole board.** `PvpService.updateStrikes` warns every live lane
together and strikes them together, one bolt each, at a random X inside each lane's
own `STEER_LIMIT_X` range. Independent per-lane clocks were the obvious shape and
the wrong one: over a three-minute match they would hand one player three bolts and
their neighbour none, and weather deciding a match is exactly what a competitive
mode can't have. Same beat, same count, different spot.

| | |
| --- | --- |
| Warning | `STRIKE_WARNING_SECONDS` (5) — shorter than the classic ten; there's no turn queue to sit through, so five seconds is two or three pieces' worth of time to build elsewhere or defend what's there |
| Gap | `STRIKE_MIN_SECONDS`–`STRIKE_MAX_SECONDS` (9–14), measured from the last bolt with the warning *inside* it, so raising a marker can't quietly slow the storm |
| Runs while | pieces are being dealt, the zone is Stormy, **and** the zone has landed — `zoneId` goes on the wire up to `ZONE_ROLL_SECONDS` before the world takes it, and a column going up mid-spin would give the reel's answer away |

**Each bolt is announced on its own lane's platform.** The classic run publishes
`LightningWarnAt` / `LightningAt` as attributes on the arena folder, and one
attribute can only ever describe one bolt — which is the real reason this was
unbuilt. A lane platform is a better announcer anyway: it's the floor its lane
builds from, so the client stands the warning column on the part that announced it
rather than on a height it would have to be told (`zoneBaseHeight` is frozen for
the whole match). `TowerZoneController` watches the arena and every lane platform
through one handler that never asks which mode is running.

**The bolt itself is the classic one**, through `TowerService.strikeColumn(x,
floorY, source)` — the storm's own driver with its three single-lane assumptions
turned into arguments. What it hits is resolved when it lands, not when the warning
went up, so seconds of building under a marker count. It needs no lane check:
`LIGHTNING_RADIUS` (26) against `LANE_SPACING` (120) means a bolt in one lane
cannot touch the tower in the next — the same arithmetic that already made a
Lightning *block* safe in a match.

Two edge cases are handled where they'd otherwise bite. A lane **seated during a
warning** isn't struck by it (pending bolts are keyed by the platform, so a
recycled seat can't inherit somebody else's bolt) and joins the next round of them.
A lane **retired mid-warning** takes its column with it, because the marker lives
on the platform that just left the world.

## The camera

The HUD's bottom-right button is the same button it always was, doing the PVP job.

| Shot | When | Frames |
| ---- | ---- | ------ |
| Lane tracking | Default | Your lane's X, your tower's top, stretched up to hold the piece you're aiming — the classic `trackingShot`, given an X |
| Map | Button on, **or** you have no lane, **or** `RESULTS` | The lanes **in play**: centred between the outermost taken seats, wide enough to hold them, the tallest tower up |

**The map shot scales to how many lanes there are.** `PvpLanes.spanBetween` takes
the outermost taken seats and returns the centre line between them plus half the
width they span; the shot aims at that X and stands back far enough to cover that
width. A two-player match is two towers filling the screen rather
than two towers adrift in four empty lanes' worth of sky — and since the low seats
fill first, a fixed shot on the origin wouldn't even have left them *centred*.

The lanes themselves never move for this. Seats stay fixed (slot 2 is slot 2
whatever the turnout) so a tower can't slide sideways under the camera watching
it — the towers hold still and the camera moves. The span is measured across the
outermost taken slots rather than counted, so a lane retired out of the middle
doesn't collapse the framing onto the survivors.

Width is what decides the distance, so the shot gets its own half-width (the span
`+ MAP_PADDING`) and its own ceiling (`MAP_MAX_DISTANCE`, 700 vs the classic 420);
a full board is 600 studs across and the classic ceiling would crop the outer two
lanes off the sides. A lane's half-width is `CAMERA_MIN_HALF_WIDTH` (34), not the
platform's 24: a tower overhangs its slab by the steering limit, and framing to
the slab would crop that off the outer towers.

A player with **no lane** — spectating, or the match was full when they arrived —
gets the map. There is no "their" tower to ride, and parking on an empty seat would
show them a bare platform for three minutes.

The standings are the point of the last ten seconds, so `RESULTS` frames the board
whatever the toggle was set to.

Two classic behaviours are explicitly switched off for the duration: the
`PHASE.GAMEOVER` wide shot (it would frame a tower demolished three minutes ago)
and the **storm shake** — `stormEndsAt` belongs to a round that isn't running, and
unguarded the shake fires for a deadline that doesn't exist. The clock is held for
the whole match now (see above) so it no longer expires mid-match, but the guard
stays: the camera shouldn't be reading the classic round's deadline during a match
whatever that deadline happens to say.

## Aiming

Unchanged, and that's the point. One implementation covers both modes:

- `TowerController.isAiming()` replaces `isMyTurn()` at every gate. "My turn" is a
  statement about a queue; in PVP everybody is holding a piece at once. In the
  classic game the two are the same answer.
- `TowerController.laneOriginX()` is the world X a placement is measured from — 0
  in classic, your lane centre in PVP. `TowerAimController` captures it once per
  piece and adds it back when it draws.
- **The wire is lane-relative.** `Packets.Place` / `Packets.Release` are unchanged;
  `x` just means "from my lane centre" now. That's what makes the server's clamp
  the same clamp in both modes — and it's why a client can't aim into somebody
  else's lane by sending a bigger number.
- Mouse pointing gives a *world* X, so `pointAt` subtracts the lane before
  clamping. Point at a neighbour's tower and your piece stops at the edge of your
  own lane, which is the honest answer.
- The aim, input and pointer controllers all subscribe to **both** stores, because
  in PVP the piece arriving is announced on the match packet rather than the turn
  packet.

## The HUD

Its own root presentation (`PvpPresentation`), registered beside the classic one.
Each renders `nil` while the other owns the board, so exactly one is on screen and
neither has to know what the other draws. A single component that tried to be both
would be a file where every line asks which mode it's in.

```
        ┌────────────────────────┐              ┌─────────────────┐
        │ 42.5 studs  2:14   2nd │  (◕)         │    STANDINGS    │
        └────────────────────────┘  drop        │ ➊ 👤 Goblin  87 │
              Snowy Zone            clock       │ ➋ 👤 You     42 │ ← your row
        ┌────────────────────┐                  │ ➌ 👤 Stack   38 │
        │                    │  what it does,   │ 4  👤 Noot    21 │
        │ Blocks are         │  for 10s after   │ 5   Empty lane  │
        │ slippery!          │  the reel lands  │ 6   Empty lane  │
        └────────────────────┘                  └─────────────────┘

                                                                     (🔍)
                                                              ┌─────────────┐
  Move — A / D…            T-Shape       [stick][TURN][DROP]  │  💵   1250  │
  ↑ controls hint, bottom-left                                └─────────────┘
```

- **The corners are the classic HUD's corners.** The controls hint is bottom-left
  and the money counter bottom-right with the camera toggle stacked above it, at
  the same offsets and from the same components — a player who learned where those
  live in a classic round shouldn't have to learn again per mode. Both were wrong
  here at first: the counter wasn't rendered at all, and the hint was passed no
  position, so it fell to the frame's origin in the **top**-left under Roblox's own
  topbar.
- **The top bar is one line and one panel.** Your height, the clock, your place:
  the clock is the middle third at twice their tier, because it's the number read
  constantly and they're what you check between pieces. It used to be two stacked
  panels — a clock over a stats row, each with its own outline — spending 132px of
  the sky the towers grow into on three numbers that fit in 64.
- **The standings board is sized for a full lobby** and holds that size at every
  player count. A board that grew a row every time somebody joined would shuffle
  the whole right edge mid-match. The seats nobody is in are **drawn as empty
  lanes**, so the reserved height reads as part of the board rather than as a board
  that failed to fill.
- **A row is a fill, not a panel.** Place disc (gold / silver / bronze for the top
  three), headshot, name, height — all drawn on the board's own glass. Six nested
  panels, each with its own 4px outline, is what made the old board read as a
  spreadsheet.
- **Your row is marked with a gold edge and a wash**, rather than painted gold: the
  yellow gem surface at row height swamped the name it was meant to point at.
- **The drop dial flanks the bar** rather than sitting in it — the same rule as the
  classic turn dial, for the same reason: a dial that comes and goes with every
  piece must not be able to resize the readout beside it.
- **The countdown and the final standings are the only centred things**, and both
  are up while nothing is being aimed, so neither can cover a tower being built.
- **At RESULTS the top bar and the live board go away.** The results panel says
  everything they were saying, so the last ten seconds are the towers with one
  surface over them.
- A spectator's height reads **"Watching"** rather than 0.0 studs, which would be a
  lie rather than an absence.
- **The reel is the only animated thing in the column**, and it keeps the row
  height it had as a plain label. Its description card grows *downwards*, off the
  bottom of the column, where there is nothing to push around.

### The final standings

```
        ┌───────────────────────────────────┐
        │          FINAL HEIGHTS            │
        │ ┌───────────────────────────────┐ │
        │ │ ➊ 👤 Goblin  WINNER 87.5 studs│ │  gold wash, taller
        │ └───────────────────────────────┘ │
        │ │ ➋ 👤 You            42.5 studs│ │  gold edge — you
        │ │ ➌ 👤 Stackmaster    38.0 studs│ │
        │ │ 4  👤 Nootnoot      21.5 studs│ │
        └───────────────────────────────────┘
```

- **The winner's row is the answer to the match**, so it's taller, washed in the
  gold of its own medal, and says WINNER — or **YOU WIN!** when it's yours.
- **The panel's height is measured, not automatic.** `ui.Panel` draws a fixed-size
  surface: handed height 0 with an auto-sizing list inside it, it painted a sliver
  of glass and let every row hang off the bottom, unbacked, over the towers. The
  list and the surface are sized off the same arithmetic now — title, winner row,
  one row per remaining lane, padding — so a three-player match gets a
  three-player panel.
- **It's the one rounded, outline-less surface in the game** (`rounded = true`,
  `stroke = false` on `ui.Panel`). Every other panel is chrome at the edge of the
  screen, where the outline is what holds it apart from the sky. This one lands
  dead centre with the match over and nothing being aimed behind it, and a
  hard-cornered outline made the last thing anyone looks at read as one more HUD
  panel. Its padding is plain `theme.padding` rather than the usual
  `padding + strokeThickness`, because that sum exists to clear a stroke this
  panel doesn't draw.

### On a phone

The HUD is authored in plain offsets against the 1280×720 reference and rides the
one root `ScaleLayer`, so it needs nothing per-device: no aspect constraints, no
second scale layer, no breakpoints. `SteerStick` reads `AbsolutePosition` but only
ever as a *ratio* against its own track, which is scale-free — see
[layout-surfaces.md](layout-surfaces.md).

**Landscape is clear at every size tested; portrait phones are not.** The scale
clamps at `0.5` and the canvas comes out ~720–780 units wide instead of 1280, and
this HUD spends its width from both edges at once — a 360-wide bar centred with
the 74 drop dial flanking it, against a 268-wide standings board pinned right.
Those meet when the canvas drops below **1124 units**:

| Canvas | What overlaps |
| --- | --- |
| 1280 and up | nothing |
| 1558 (phone landscape) | nothing |
| 780 (portrait, 390×844) | drop dial over the board by 172; top bar by 78 |
| 720 (portrait, 360×800) | dial by 202, bar by 108, touch row over the camera toggle by 11 |

Not fixed, because both fixes are decisions rather than plumbing: reflow the board
below the top column (costs ~200 units of sky on every device, since the column
grows while the zone reel is rolling), or lock the place to landscape with
`ScreenOrientation`. The second is the honest one for a mode with a fixed side-on
camera and a 578-wide thumb row, but it's a place-wide call.

Worth knowing either way: the camera toggle is 62 units, which is **31 device
pixels** at the 0.5 floor — under the ~44px a thumb reliably hits. TURN and DROP
are 88 tall, so they land right on it.

## Rewards

Paid once, at `RESULTS`, through the ordinary `CashService.award` — so the 2x Cash
gamepass multiplies it like everything else.

| Award | Who |
| ----- | --- |
| `CASH_PER_STUD` (3) per stud | Everyone, for their own tower |
| `CASH_WINNER` (150) | The tallest tower |

Their tower, their studs — unlike the classic per-stud award, which pays whoever
happened to place the block that set a shared record. The winner's bonus is
deliberately small next to the per-stud award: the height *is* the prize, and a
winner-takes-all purse would make the last thirty seconds pointless for everyone
but the leader.

`Blocks Placed` counts every drop, as it does in classic. `Biggest Height` is
recorded per player via `TowerStatsService.recordPlayerHeight` — the classic
`recordHeight` credits the whole room because there is one shared tower, and in
PVP the tower is yours.

## Testing it

The mode is otherwise a full storm clock away — five minutes of classic play, then
a poll four other people get a say in. So:

```
gamemode pvp
```

(alias `pvp`) ends the round now and plays PVP next, skipping the vote. It routes
through the real round break, so what it produces is the round the vote would have
produced. Takes any gamemode id; refuses mid-checkpoint and mid-break for the same
reason the action products do.

`blockrate 1` beside it makes every piece a special, which is the fast way to see
whether a hazard can reach across a lane boundary.

## Files

| File | Realm | Role |
| ---- | ----- | ---- |
| `PvpConstants.luau` | shared | Lane layout, the three clocks, the odds, the rewards, `PHASE`, `Presentations` |
| `PvpLanes.luau` | shared | The one place a slot becomes a world X |
| `PvpPackets.luau` | shared | ByteNet: one `State` packet carrying every lane |
| `PvpHUD.ui.luau` | shared | Dumb HUD: clock, your height and place, standings, countdown, results |
| `PvpHUD.story.luau` | shared | UI Labs story — every prop on a slider, all three phases |
| `ZoneReel.ui.luau` | shared | The zone line: spins through the names for the roll window, lands, says what the zone does |
| `ZoneReel.story.luau` | shared | UI Labs story — `autoRoll` runs the spin/land/describe loop on its own |
| `PvpService.server.luau` | server | The match: lanes, the poll, the zone clock, the standings, the payout |
| `PvpController.client.luau` | client | Match store + `myLane` / `laneOriginX` / `standings` |
| `PvpView.client.luau` | client | Container: subscribes, runs the clocks, resolves names |
| `PvpPresentation.client.luau` | client | Registers the HUD as a UIRegistry root |

Touched in TowerGame: `TowerService` (the block engine API, `heldBy`, the round
break hand-off), `Gamemodes` (the ballot entry), `Zones` (`Zones.roll`, the shared `warning` line),
`TowerStatsService` (`recordPlayerHeight`), `TowerController` / `TowerAimController`
/ `TowerInputController` / `TowerPointerController` (lane-relative aiming),
`TowerCameraController` (the two shots), `TowerZoneController` (two packet sources,
lane-local weather, the deferred paint), `TowerView` (stands down), `Commands`
(`gamemode`).

## Studio setup

**None beyond what the classic game already wants.** Lane platforms are generated;
every zone asset is the same one classic uses and degrades to "leave it as it was"
when missing.

Two things to know if you're building a map:

- **The board occupies `x −324 … +324`** at the classic base's altitude (the map
  shot frames a little wider than that, to `±334`), and it stands up to 700 studs
  back on +Z. Nothing may sit between `z = +6` and `z = +700` across that whole
  width, or a map shot will frame it instead of the towers.
- **The classic base is taken off the board for the length of a match** and put
  back after — `setBaseOnBoard` in `TowerService`, called around `runMatch`. It
  sits at `x = 0`, which with symmetric seats is the gap between slots 2 and 3: a
  seventh slab at lane altitude that nobody is building on. It's parented away
  rather than hidden, so it takes its shadow, its collisions and anything you've
  hung off it with it, and comes back the same part, tag and all. `baseTopY` is
  untouched — the lanes are built at that altitude and every client's camera reads
  it off the arena attribute for the whole match.

Set **`Players.MaxPlayers` to 6** in Game Settings; a script can't.

## Not built yet

- **Only ever play-tested solo — one lane.** A full match has been run start to
  finish with a single player: lanes build, the clock runs, the standings pay out,
  the camera frames the lane, and the classic base leaves and comes back on cue.
  Nothing with **two or more towers on the board** has been exercised, so the
  numbers most likely to be wrong first are still `LANE_SPACING` (does a bomb
  really stay in its lane?), `MATCH_SECONDS` and `PIECE_GAP_SECONDS`.
- **The storm has never been seen with two lanes in it.** Strikes are built (see
  [The storm](#the-storm)) and verified against a solo lane — warnings raised in
  the right column, bolts resolving onto the tower's top — but "six markers on
  screen at once" is exactly the kind of thing that reads differently with a board
  full of them.
- **No spectator lane picker.** A player with no lane watches the map and can't
  choose a tower to follow.
- **Pieces come from one shared bag**, so all six lanes draw the same sequence.
  Invisible without a next-piece preview.
- **The streaming focus stays on the arena centre.** Fine at these distances (the
  outer lane is 325 studs out, well inside `StreamingTargetRadius`), but it isn't
  *tracking* the way the classic one does, so a very tall PVP tower would be the
  first thing to test it.
- **No end-of-match camera move onto the winner.** The results shot is the map.
