# Platform layouts

The ground a run is built on, as a Studio asset rather than a constant.

The game used to stand on one shape: `Constants.PLATFORM_SIZE`, a 48 × 4 × 8 slab,
used for the base and for every checkpoint floor above it. That slab was a number
in a file, so the only ground the game could ever have was the one shape. A
**layout** is a Model of one or more slabs, and the base and every checkpoint are
now stamped out of one — so a floor can be two slabs with a gap down the middle,
three narrow columns, or a high centre between two low wings.

The point is strategic, not decorative. A gap is a column where a piece falls
past and is swept, so the ground itself becomes a question the tetromino in your
hand has to answer.

**Entirely optional.** A place with no layouts folder — or no layout eligible for
the floor being built — gets the generated slab it always got. That's what keeps
Boil bootable in an empty place, and it's the path a downstream project that never
opens Studio stays on.

## Where they live

`ServerStorage.TowerPlatformLayouts` (`Constants.PLATFORM_LAYOUTS_FOLDER`), one
Model per layout, plus a `README` StringValue carrying the same rules as this doc
so they're on hand in the explorer. Server-only: the client never needs them and
reads the one number it cares about — the scoreline — off the arena's `BaseTopY`
attribute, exactly as before.

**This is a Studio asset, so it's yours to maintain.** Rojo doesn't sync it and
nothing in `src/` recreates it.

## Authoring rules

| Rule | Why |
| --- | --- |
| Every BasePart in the Model is a slab | Non-parts are ignored; there's no other marker to get wrong |
| `Position.Z = 0`, `Size.Z = 8` | Blocks live on a 2D slice. A slab off the play plane is a slab nothing can land on — the layout is **rejected with a warning** at load |
| **The pivot is the scoreline** | The layout is dropped in by its pivot and height is measured up from it |
| Stay inside `x = −30 … +30` | A piece steers to ±`STEER_LIMIT_X` (22) and overhangs 8 past that. Slab outside that is slab nobody can reach |
| Leave slabs in the Default collision group | Same as the base and checkpoints — a Ghost block falls through blocks but not through floor |

Slabs are force-anchored at build time; an un-anchored slab is a floor that falls
out from under the run, which is too expensive a mistake to leave to the author.

### The pivot is the contract

The pivot is the one thing that isn't derived from the geometry, and it's what
makes the awkward layouts possible. It is *not* "the top of whichever slab is
highest" — the author decides which surface is the ground:

- A slab **above** the pivot is a wall or a lip.
- A slab **below** the pivot is a hole you climb out of before you score anything.

`Pedestal` is the case that proves it: a 16-wide centre at the pivot and two wings
eight studs down. `BaseTopY` stays on the centre, so the wings are wider ground
that costs you two blocks of climbing, rather than a scoreline that quietly sank.

### Gaps, measured against pieces

A gap is only a gap if a piece can't casually bridge it. Cells are
`BLOCK_SIZE` (4) studs:

| Gap | What crosses it |
| --- | --- |
| 4 | Any 2-cell piece laid flat |
| 8 | A 3-cell run — L, J, S, Z, T laid flat |
| 12 | The I-piece, with 2 studs of bearing each side |
| 16 | The I-piece exactly spans it, with nothing to spare — so it falls |
| 20+ | Unbridgeable. Two separate towers for the whole run |

## Attributes

All four are optional; the defaults are what a freshly duplicated Model does
without being configured.

| Attribute | Default | Meaning |
| --- | --- | --- |
| `Roles` | both | `"base"`, `"checkpoint"`, or `"base,checkpoint"` — where the layout may be used |
| `Weight` | 1 | Relative odds against the other eligible layouts. 0 disables it |
| `MinCheckpoint` | 0 | Earliest floor it may be built on. 0 is the base, 1 the first checkpoint |
| `Notes` | — | Free text, for you |

`MinCheckpoint` is the difficulty dial and the one worth tuning first: it keeps
the clever ground away from the opening minute, so a run starts on something a
new player can read.

## What ships

| Layout | Slabs (studs from lane centre) | Gaps | Weight | Earliest floor |
| --- | --- | --- | --- | --- |
| Plain | −24…24 | — | 3 | base |
| Split | −24…−4, 4…24 | 8 | 2 | base |
| Stepped | −24…0, 0…24 *(8 low)* | — | 2 | 1 |
| Pillars | −24…−12, −6…6, 12…24 | 6, 6 | 2 | 2 |
| Pedestal | −28…−12 *(8 low)*, −8…8, 12…28 *(8 low)* | 4, 4 | 2 | 2 |
| Chasm | −30…−6, 6…30 | 12 | 1 | 3 |

Plain is weighted heaviest on purpose: a run where every floor is a twist has no
baseline to be a twist against.

## How it's wired

`PlatformLayouts.server.luau` reads the folder once, validates, and offers two
calls. `TowerService` uses them in exactly two places.

| Call | Does |
| --- | --- |
| `pick(role, checkpoint)` | A weighted random eligible layout, or nil to fall back to the generated slab |
| `build(layout, floorY, parent, name)` | Clone, pivot onto `floorY`, flatten, return the slabs |

**`build` flattens.** The Model is a mould, not the thing itself: the slabs are
reparented to the arena and the empty Model destroyed. Two reasons — the arena's
children are walked for held pieces (`TowerAimController.findOwnPiece` looks for a
Model stamped with a user id), so leaving a Model there puts ground into a lookup
that should only ever find pieces; and `platforms` is a flat list of BaseParts
that every measurement already iterates.

Slabs come out named for the floor they are (`Checkpoint3_SlabLeft`, `Base_Slab`)
and carry a `Layout` attribute naming the layout they came from, which is what
makes a play test legible in the explorer.

### Why this needed almost no new rules

A floor was **already a list of parts**. `platforms: { BasePart }` has held the
checkpoint slabs since there was more than one floor, and every consumer of it was
already per-part and X-aware:

- `restingTopY(x)` takes the highest slab whose column contains `x` — so a gap is
  already "no slab answers for this column".
- `measureLane` takes the max top, and starts at `floorY`, so a slab below the
  scoreline can't drag the height negative.
- `blastPlatformsBelow` throws each slab individually.

So a piece dropped into a gap already fell past and got swept. The wiring only had
to *choose* a layout and *stamp it out*.

### The base

`buildBase` answers in three steps, in order of how much the place has asked for:

1. A part tagged `BASE_TAG`. Someone built their own base in Studio and this
   file's opinion isn't wanted — including its opinion about layouts. Two
   exceptions, both asserted on adoption: it is **anchored**, and it wears
   **`FLOOR_PHYSICS`**. A floor that falls away is a broken run, and a floor with a
   stock Studio part's physics (friction 0.3, elasticity 0.5) bounces what lands on
   it and lets the rest slide off — which is what an authored base did until this
   was added. Everything else is the author's: size, position, colour, material.
2. A layout eligible for floor 0.
3. The generated prototype slab.

It returns the slabs *and* the scoreline, and the scoreline is the pivot rather
than a slab top for the reason above.

The base is **not** in `platforms` and is never demolished. It's tracked as
`baseSlabs`, a list of `{ part, parent }` pairs, because a PVP match takes the
base off the board and has to put it back exactly where it was — and with layouts
that's now several parts, which may include a tagged part living anywhere.

### The one thing that had to change

The checkpoint demolition cutoff. It used to be drawn one `PLATFORM_SIZE.Y / 2`
below the new floor's scoreline, which is fine when a floor is one slab of known
thickness. A layout may hang slabs *below* the scoreline, and that cutoff would
have the new floor demolish its own wings the instant it landed — Pedestal's sit
eight studs down, well under it.

So the cutoff is now the bottom of the **lowest slab in the new floor**:

```lua
local cutoff = math.huge
for _, slab in newFloor do
    cutoff = math.min(cutoff, slab.Position.Y - slab.Size.Y / 2)
end
```

### The entrance animation

`playInSlab` runs per slab rather than per floor: each enters as a sliver at its
own centre line and stretches outward. A Split floor therefore opens as two
slivers spreading apart, and the gap is the last thing you see appear — which is
exactly the thing the player needs to notice.

## Not wired

- **PVP lanes still use `PLATFORM_SIZE` directly.** Six lanes of ground is a
  design question layouts don't answer on their own: one layout shared by all six
  seats (fair, and the standings stay comparable) or an independent roll per lane
  (chaotic, and a player can lose to their ground rather than to a neighbour).
  Decide that before wiring it.
- **No layout is picked per *zone* or gamemode.** A Stormy floor and a calm one
  draw from the same set.

## Testing it

`skipstage` (or `skip`) in Cmdr runs a full checkpoint, which is the fastest way
to roll floors. To force one layout, set every other `Weight` to 0 in Studio and
restart the play session — the folder is read once per server, so attribute edits
need a restart to take effect.

## Play-tested

Solo, one session: base from `Plain`, checkpoints 1–3 rolling `Plain`, `Plain`,
`Chasm`, with the two-slab Chasm floor surviving its own demolition and pieces
resting on both sides of the gap. Then a forced run of `Pedestal` as both base and
checkpoint 1, confirming `BaseTopY` stays on the pivot (42, not the wings at 34)
and that the wings survive the demolition cutoff that would have eaten them
before the fix. A PVP round during the same session took all three Pedestal base
slabs off the board together and put them back.

Not exercised: `Split`, `Stepped` and `Pillars` in a live round — same code path
as `Chasm` and `Pedestal`, but no session has rolled them yet.
