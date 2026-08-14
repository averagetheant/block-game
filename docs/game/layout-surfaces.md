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

That last part is only true because the layer is **sized `1 / scale` of the
screen**, not `1, 1`. A `UIScale` transforms its parent's whole subtree about the
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
