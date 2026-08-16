# PVP

The every-player-for-themselves round. Six lanes, six platforms, no turns: every
player holds their own piece at the same time as everyone else and builds as high
as they can before one shared clock runs out. Whoever's tower is tallest when it
stops wins, and the standings go up over the towers they belong to.

It's a **gamemode**, not a separate place — it wins the ordinary
[GamemodeVote](GamemodeVote.md) ballot and replaces the round that would have
followed. Vote it twice and you play it twice.

Prototype status: built end to end and **not yet play-tested**. See
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
`EXPLOSION_RADIUS` (46) of itself. 120 leaves ~68 studs of air between two towers,
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

**Special blocks are a flat 30%** (`SPECIAL_CHANCE`), fed through the same
`blockTypeChance` lever Roulette uses — a flat promise that bypasses the
escalating curve *and* `BlockTypes.MAX_CHANCE`. The curve is a function of
checkpoints cleared, and a PVP match clears none, so it would sit at its 3% floor
for the whole three minutes.

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

Everything a zone does still applies: gravity (Space), snow friction, Retro studs,
the fog, Night's per-block lights, the sky. The server calls
`TowerService.applyZone`, which dresses every standing block and every held piece
and writes `workspace.Gravity` — but deliberately does **not** touch the classic
state packet, which is stale for the whole match. The zone rides the PVP packet
instead, and `TowerZoneController` reads whichever packet is live.

**Weather follows your own lane.** `followTower` positions the rain/snow emitter
over `PvpLanes.xOf(myLane.slot)` at your own tower's height — snow falling over the
middle of a six-lane board would be weather nobody is standing in.

**Lightning is off during a match.** The whole mechanism is single-lane by
construction: one warning column, standing on one floor, announced by one
attribute on the arena. Striking only the middle lane would be worse than not
striking at all. See [Not built yet](#not-built-yet).

## The camera

The HUD's bottom-right button is the same button it always was, doing the PVP job.

| Shot | When | Frames |
| ---- | ---- | ------ |
| Lane tracking | Default | Your lane's X, your tower's top, stretched up to hold the piece you're aiming — the classic `trackingShot`, given an X |
| Map | Button on, **or** you have no lane, **or** `RESULTS` | The whole board: `x = 0`, every lane across, the tallest tower up |

The map shot is centred on the arena origin because the seats are symmetric about
it — a framing that re-centred on whoever happened to be playing would swing the
board sideways every time somebody joined. Width is what decides its distance, so
it gets its own half-width (`PvpLanes.halfWidth() + MAP_PADDING`) and its own
ceiling (`MAP_MAX_DISTANCE`, 700 vs the classic 420); six lanes is 600 studs across
and the classic ceiling would crop the outer two off the sides.

A player with **no lane** — spectating, or the match was full when they arrived —
gets the map. There is no "their" tower to ride, and parking on an empty seat would
show them a bare platform for three minutes.

The standings are the point of the last ten seconds, so `RESULTS` frames the board
whatever the toggle was set to.

Two classic behaviours are explicitly switched off for the duration: the
`PHASE.GAMEOVER` wide shot (it would frame a tower demolished three minutes ago)
and the **storm shake** — `stormEndsAt` is a stale number for the whole match, and
unguarded it runs out somewhere in the middle and shakes the camera for a deadline
that doesn't exist.

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
                     [  2:14  ]              match clock (red under 30s)
                  42.5 studs   2nd           your height and place
                    Snowy Zone               the zone            (◕) drop clock
                                             ┌──────────────┐
                                             │  STANDINGS   │
                                             │ 1 Goblin  87 │  ← always 6 rows
                                             │ 2 You     42 │     your row is lit
                                             │ …            │
  Move — A / D…            T-Shape           [stick][TURN][DROP]      (🔍)
```

- **The standings board is sized for a full lobby** and holds that size at every
  player count. A board that grew a row every time somebody joined would shuffle
  the whole right edge mid-match.
- **The drop dial flanks the column** rather than sitting in it — the same rule as
  the classic turn dial, for the same reason: a dial that comes and goes with every
  piece must not be able to resize the readout beside it.
- **The countdown and the final standings are the only centred things**, and both
  are up while nothing is being aimed, so neither can cover a tower being built.
- A spectator's height reads **"Watching"** rather than 0.0 studs, which would be a
  lie rather than an absence.

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
| `PvpService.server.luau` | server | The match: lanes, the poll, the zone clock, the standings, the payout |
| `PvpController.client.luau` | client | Match store + `myLane` / `laneOriginX` / `standings` |
| `PvpView.client.luau` | client | Container: subscribes, runs the clocks, resolves names |
| `PvpPresentation.client.luau` | client | Registers the HUD as a UIRegistry root |

Touched in TowerGame: `TowerService` (the block engine API, `heldBy`, the round
break hand-off), `Gamemodes` (the ballot entry), `Zones` (`Zones.roll`),
`TowerStatsService` (`recordPlayerHeight`), `TowerController` / `TowerAimController`
/ `TowerInputController` / `TowerPointerController` (lane-relative aiming),
`TowerCameraController` (the two shots), `TowerZoneController` (two packet sources,
lane-local weather), `TowerView` (stands down), `Commands` (`gamemode`).

## Studio setup

**None beyond what the classic game already wants.** Lane platforms are generated;
every zone asset is the same one classic uses and degrades to "leave it as it was"
when missing.

Two things to know if you're building a map:

- **The board occupies `x −324 … +324`** at the classic base's altitude, and the
  map shot stands up to 700 studs back on +Z. Nothing may sit between `z = +6` and
  `z = +700` across that whole width, or a map shot will frame it instead of the
  towers.
- **The classic base sits between slots 2 and 3** (it's at `x = 0` and the seats
  are symmetric about it). It's harmless — the same altitude, out of every lane's
  steering range — but it's visible in the map shot.

Set **`Players.MaxPlayers` to 6** in Game Settings; a script can't.

## Not built yet

- **Never play-tested.** Written end to end, run zero times. The numbers most
  likely to be wrong first are `LANE_SPACING` (does a bomb really stay in its
  lane?), `MATCH_SECONDS` and `PIECE_GAP_SECONDS`.
- **No lightning.** Stormy still rains and still destroys struck blocks, but the
  strike mechanism is single-lane and is switched off for a match. Making it work
  means a warning column per lane, which means the warning stops being one
  attribute on the arena.
- **No zone banner.** The classic HUD's warning card is TowerHUD's; the PVP HUD
  names the zone in its top column instead. A banner for special zones is worth
  adding.
- **No spectator lane picker.** A player with no lane watches the map and can't
  choose a tower to follow.
- **Pieces come from one shared bag**, so all six lanes draw the same sequence.
  Invisible without a next-piece preview.
- **The streaming focus stays on the arena centre.** Fine at these distances (the
  outer lane is 325 studs out, well inside `StreamingTargetRadius`), but it isn't
  *tracking* the way the classic one does, so a very tall PVP tower would be the
  first thing to test it.
- **No end-of-match camera move onto the winner.** The results shot is the map.
