# Layout surfaces

Seam #2 is *how a screen is arranged*. Two surfaces, chosen per screen:

1. **Code primitives** (the default) — `Stack` / `Row` / `Grid` / `Slot`.
2. **Studio-extract skeleton** (for hero screens) — hand-built in Studio, extracted
   to a style-stripped skeleton, filled with skinned content via a portal. *Deferred*
   — the design is below; build it when a screen actually needs it.

## Code primitives (`src/shared/ui/`)

Transparent, structure-only. They wrap `UI*Layout` / `UIPadding` / sizing / anchors
and draw **nothing** — no background, no stroke. Put skinned primitives inside them.

| Primitive | Wraps | Notes |
| --------- | ----- | ----- |
| `Stack` | UIListLayout (vertical) | gap, padding, alignment, flex |
| `Row` | Stack (horizontal) | same props, forces horizontal |
| `Grid` | UIGridLayout | cell size/padding, columns; children are **direct** (the layout only sizes direct children — don't wrap a cell, animate it with a child `UIScale`) |
| `Slot` | a named transparent Frame | a positioned region; also the named target for the future portal bridge |

Each has a UI Labs story. Default to these for most screens; they keep arrangement
in code where it's diffable and live-tunable.

Honor the standing rules: pad against a stroked edge with `padding +
strokeThickness`, and center new feature UIs by default (off-center is for large
content surfaces).

## Stacking (`ui.layers`)

Every feature's UI mounts as a **sibling root** under the one ScaleLayer, so what
draws in front of what is decided by the ZIndex those roots carry — and by nothing
else. Left unset they all sit on Roblox's default of `1`, and the tie is broken by
the order React happened to mount them in, which is a table iteration: stable
enough to look right in Studio, and free to flip the day another feature
registers. That is how the daily rewards window ended up behind the PVP standings
board.

Two features that must stack in a set order therefore need a number they both
know, and neither may read the other's constants (a feature has to be removable
without its neighbour noticing). So the scale lives in `ui.layers`, ordinal and
naming nobody:

| Layer | Value | For |
| ----- | ----- | --- |
| `underlay` | −100 | Behind the game's own HUD: a standing status surface that must be findable but never in the way of what it describes — the "Not playing" badge is the case it exists for |
| `hud` | 1 | The game itself: HUDs, rails, world-anchored readouts. Roblox's own default, so an unmarked root is already here |
| `window` | 100 | Frames and windows opened over the game |
| `flourish` | 900 | Feedback that must never be buried — a payout burst, a toast: the game answering something the player just did |

Gaps of 100 so a feature can slot its own pieces between two layers — a scrim just
under its window, a badge just over its panel. Those in-between numbers are
*child* ZIndex inside one root, which is where they belong: only the root's number
is anybody else's business.

**One surface, one layer.** A child can never draw lower than its own root: the
ScreenGui runs `ZIndexBehavior.Sibling`, so a root's ZIndex places its whole
subtree and the numbers inside it only sort against each other. A feature with two
surfaces that must stack differently needs **two roots**, not one root and two
child ZIndexes — see `TowerAfkView` (the card, over everything) and
`TowerSpectatorView` (the badge, on `underlay`), which were one root until exactly
this came up.

The cost of `underlay` is worth stating: anything on it is by definition
coverable, and where another root overlaps it that root takes the clicks. Don't
put a control there that has to be reachable at all times.

Deliberately **not** a theme token. A skin decides how a surface looks, never
whether it is in front; "does my window cover the HUD" must not have a per-skin
answer.

## Viewport scale

Arrangement is authored in **pixels against a 1280×720 reference** — a `62`-tall
panel, a `20` edge margin, `textSize = 32`. Pixels are absolute, so left alone
those numbers eat a phone screen whole. `src/client/init.client.luau` mounts one
`ui.ScaleLayer` as the React root: a Frame holding a single `UIScale` fitted to
the viewport (`min` of the two axis ratios, clamped to `[0.5, 1]`).

Everything below it shrinks together — sizes, margins, TextSize, stroke, padding
— and stays anchored where it was: a bottom-right panel stays bottom-right, just
smaller, with a proportionally smaller gap to the corner.

### The halving, and what it means for text

That `0.5` floor is the number to design against: **every pixel you write is
roughly halved on a phone.** Desktop intuition — 16px body copy, 14px captions —
picks text sizes one or two tiers too small here, because the reference frame is
not a CSS pixel grid. `theme.textSizeRegular` (`32`) renders at ~16px on a phone,
which makes it the *floor* for anything a player reads, not the middle of the
ladder. `textSizeSmall` (`24`) lands at ~12px and `textSizeXS` (`20`) at ~10px;
both are decorative tiers that need a reason.

The practical rule: when a label doesn't fit, **grow the box, don't shrink the
text.** Trimming a tier by a few pixels to squeeze into a fixed height (`textSize
= theme.textSizeRegular - 5`) reads as fine in the UI Labs preview, which runs at
full scale, and is unreadable on the device that matters. Size heights from the
tier (`TIER + padding`) so re-tiering a label moves its row instead of clipping
it. Text that genuinely sizes to its container rather than to the ladder — an
emoji glyph, a close-button `X` — is the exception, and should derive from the
box explicitly (see `Constants.GLYPH_FIT` in the Reactions feature).

### Fitting text on a real device

The scale is uniform, so a screen that fits at the reference "obviously" fits
everywhere. Text is the exception, and it's why copy in the shop, the inventory
and the vote used to lose its last line on a phone and nowhere else.

Glyph metrics don't scale linearly. At the ~0.5 UIScale a handset gets, every
advance and every line height rounds to a whole device pixel, and the rounding
goes up as often as down — so a sentence that wraps to exactly two lines on a
monitor can need three on a phone. A `TextLabel` doesn't squeeze the extra line
in: it doesn't draw it. Same for a box sized to exactly `tier * rows`, where a
line that grows by one pixel no longer fits at all.

Three rules, in the order you should reach for them:

1. **Size a text box as `tier * rows + slack`, never the bare product.** Eight
   pixels is the house slack. A box with no headroom is a line waiting to be
   dropped.
2. **Grow the box before you shrink the tier** — the rule above, applied to the
   whole surface rather than one label. If a panel can't hold its copy, the
   panel is the wrong size: `GamemodeVote`'s went from 190 to 240 wide for
   exactly this reason.
3. **Leave `fit` on as the backstop.** `ui.Text` renders a
   `UITextSizeConstraint` capped at the authored `textSize`, so a label can give
   a few pixels back rather than clip — never grow. It's on by default for
   `wrapped` copy, off for single-line labels (pass `fit = true` for a label
   that must stay inside its box — a name out of a catalog, a nav word over an
   icon), and ignored alongside `automaticSize`, since a box that grows to its
   text and text that shrinks to its box are two answers to one question. The
   floor is 80% of the tier: past that the box is the bug, and clipping is the
   honest signal.

`fit` is a rescue, not a layout tool. A screen that only fits because every
label shrank is a screen that needs rules 1 and 2.

### The width budget, and where the clamp bites

The halving is the *legibility* consequence of the `0.5` floor. There's a second
one, about **space**: the scale is `min` of the two ratios, so on a screen much
narrower than the reference the clamp refuses to shrink any further and the
canvas stops being 1280 units across.

| Viewport | Scale | Canvas |
| --- | --- | --- |
| 1280×720 and up | 1.0 | 1280 × 720 |
| Phone landscape, 844×390 | 0.542 | **1558** × 720 |
| Tablet landscape, 1080×810 | 0.844 | 1280 × 960 |
| Tablet portrait, 810×1080 | 0.633 | 1280 × 1707 |
| **Phone portrait, 390×844** | 0.5 *(clamped)* | **780** × 1688 |
| **Phone portrait, 360×800** | 0.5 *(clamped)* | **720** × 1600 |

Landscape is generous — a phone held sideways gets a *wider* canvas than the
reference, because height is the binding axis. Portrait is the opposite: the
clamp holds the scale at 0.5 and the canvas comes out around **720–780 units
wide**, a little over half the reference.

So the reference is a promise about height, not width. A layout that fills the
1280 gets no warning on any desktop or any landscape device and then overlaps
itself in portrait. **Budget ~720 units of width** for anything that has to hold
together in both orientations.

Note what the fix is *not*: a per-screen breakpoint. Either the layout fits the
narrow canvas at every size, or the surface is one that only makes sense in
landscape and the place should say so (`ScreenOrientation` on the player) — the
kit deliberately has no third answer.

### Screen edges

The root ScreenGui runs `ScreenInsets = DeviceSafeInsets` with
`SafeAreaCompatibility = None`. Desktop viewports are rectangles and lose
nothing; a phone keeps the tree clear of the notch, the punch-hole, the home
indicator and the rounded corners, which is what was clipping the left rail's
icons. The Roblox topbar is deliberately *not* inset for — the HUD still draws
under it.

That inset is the one place the canvas is slightly smaller than the scale
implies: `useViewportScale` reads the camera, the layer sizes against the
insetted ScreenGui, so a notched phone gets ~5% less than the 720 units of
height the reference promises. Nothing currently reaches that (the tallest
surface is the 600-tall Window), but a full-height layout should treat ~684 as
the real budget.

Edge margins are pixels like everything else, so they halve on a phone too — a
`20` margin is ten device pixels. Anything that bleeds past its own box near an
edge (the Sidebar's labels are wider than their icons) needs the margin measured
against the *bleed*, not the box.

### Why the layer is oversized

Everything staying anchored where it was — a bottom-right panel still in the
bottom-right corner — is only true because the layer is **sized `1 / scale` of
the screen**, not `1, 1`. A `UIScale` transforms its parent's whole subtree about the
parent's `AnchorPoint` — `Scale` positions included, not just offsets — so a
full-screen layer at `0.58` would squeeze the entire HUD into the top-left 58% of
the display. Sizing the layer as an oversized *virtual canvas* and scaling it back
down maps it onto the viewport exactly instead. (Same trap `UIShell.Frame` avoids
by injecting its enter-tween UIScale into the child rather than the wrapper — a
UIScale on a full-screen wrapper "scales from the screen, not the child's own
center.")

So: **keep writing plain pixel offsets.** Don't reach for `UDim2.fromScale` sizes,
per-screen breakpoints, or `UIAspectRatioConstraint` to "make it responsive", and
don't mount a second `ScaleLayer` inside a feature. The one exception is a
measurement that crosses into the tree from real screen space (an
`AbsolutePosition` from another ScreenGui, a raw input coordinate) — divide it by
`ui.useViewportScale()` first. See [reference.md](../reference.md) § Viewport scale.

## Studio-extract skeleton (deferred design)

When a hero screen is painful to arrange in code, the plan is to let the user build
it in Studio and extract two artifacts from one hand-built UI:

- **layout skeleton** — hierarchy + sizes / positions / anchors + `UI*Layout` /
  padding + **named slots**, *style-stripped* (no colors/strokes/gradients).
- **skin styling** — colors / strokes / gradients / decoration keyed by element
  name, which becomes gem-skin content.

A **portal bridge** (`ReactRoblox.createPortal`) then renders skinned content into
the skeleton's named `Slot`s. Discipline: **Studio skeletons must be visually
neutral**, or the skin and the skeleton fight over who draws the look.

**Status:** not built. To build it, extend the `studio-import` skill / the Inspect
tool to emit the skeleton + styling split, and add the portal helper that maps
skin output into the skeleton's `Slot` names. Until a screen demands it, code
primitives cover the need — don't build the pipeline speculatively.
