# Responsive scaling

How the UI lands correctly on a 4K monitor, a laptop window, and a phone held
sideways — without a single feature reading `ViewportSize`.

Code: `src/shared/ui/Responsive.luau` (the maths + the hook),
`src/shared/ui/Canvas.luau` (the one UIScale), mounted by
`src/client/init.client.luau`. Framework, not feature — see
[framework-boundary.md](framework-boundary.md).

## The rule

**Every size in this codebase is a *design pixel*, authored against a 1920×1080
screen.** `theme.textSizeRegular = 32`, `BUTTON_SIZE = 110×88`, `RAIL_MARGIN = 20`
— all design pixels. Nothing at a call site converts them, scales them, or
branches on device. Write the layout once, at desktop sizes, and let the canvas
place it.

## The canvas

`ui.Canvas` is a full-screen Frame sized `1 / scale` of the screen with a
`UIScale` of `scale` on it. Scaled back up it renders exactly full-screen, but its
own coordinate space is `viewport / scale` design pixels across:

* scale-based positions are untouched — `UDim2.fromScale(0.5, 0.5)` is still
  screen centre on every device;
* every *offset* below it is a design pixel that shrinks with the screen;
* text, strokes and corner radii scale with it, because UIScale scales the whole
  subtree.

The client entry mounts exactly one, around `UIRegistry.getRoots()`. A feature
never mounts its own — nesting canvases scales twice.

Anything measured in *device* pixels still works: `AbsolutePosition` /
`AbsoluteSize` are post-scale real pixels, so input maths that compares them
against `InputObject.Position` (TowerGame's `SteerStick`) needs no change.

## The curve

`Responsive.scaleFor(viewport)`:

```lua
scale = sqrt(viewport.Y / 1080)                        -- the curve
scale = min(scale, viewport.X / 900, viewport.Y / 680) -- the canvas floor
scale = clamp(scale, 0.3, 1.5)                         -- sanity bounds
```

| Screen | Scale | Design canvas |
| ------ | ----- | ------------- |
| 3840×2160 | 1.41 | 2715×1527 |
| 1920×1080 *(reference)* | 1.00 | 1920×1080 |
| 1366×768 | 0.84 | 1619×910 |
| 1180×820 (tablet) | 0.87 | 1354×941 |
| 930×430 (phone, landscape) | 0.63 | 1473×681 |
| 430×930 (phone, portrait) | 0.48 | 900×1946 |

Why `sqrt` and not the ratio itself: a straight ratio preserves the *proportions*
and hands a phone 12px text. A physically smaller screen needs a proportionally
*larger* UI, not the same one shrunk, so the square root splits the difference —
the layout shrinks enough to fit while text stays readable and touch targets stay
tappable (TURN lands at 69×56 device px on a phone).

`MIN_CANVAS` (900×680) is the floor that makes the canvas a promise: the largest
surface the kit authors — Sidebar's 820×600 default `Window` — fits on every
screen. It's what binds in portrait, where the curve alone would leave the canvas
narrower than a window. Keep a new full-screen surface inside 900×680 design
pixels, or raise the floor with it.

## Chrome insets

`BoilRoot` is full-bleed (`IgnoreGuiInset = true`) so a full-screen effect — the
storm's white-out — actually covers the screen. The cost is that the Roblox
topbar, a notch, and the home indicator all sit *inside* its bounds. Edge-anchored
UI moves in past them itself:

```lua
local insets = ui.useViewport().insets  -- design pixels, ready to add
position = UDim2.new(1, -(EDGE_MARGIN + insets.right), 1, -(EDGE_MARGIN + insets.bottom))
```

`insets` covers `top` / `bottom` / `left` / `right`, is already converted to
design pixels, and updates when the phone rotates or the topbar changes shape.
Centred UI needs none of this — which is one more reason
[centred-by-default](../../CLAUDE.md) is the rule for feature UIs.

Current consumers: TowerGame's HUD (all four edges), Sidebar's rail (left),
Reactions' bar (bottom).

## `ui.useViewport()`

```lua
local metrics = ui.useViewport()
metrics.viewport  -- Vector2, real device pixels
metrics.scale     -- design px → device px
metrics.canvas    -- Vector2, design-space room the UI actually has
metrics.insets    -- { top, bottom, left, right }, design pixels
```

Re-renders on window resize, device rotation, camera swap, and topbar change (and
bails out of the update when nothing moved, so dragging a window edge doesn't
re-render the tree per frame). Reading it is *not* a licence to hand-scale — reach
for it for insets, or when a surface genuinely needs to know how much room it has.

## Tuning it

`src/shared/ui/Canvas.story.luau` renders a device-sized frame with a mock HUD
inside a canvas told to pretend that's the screen — pick Phone/Tablet in UI Labs
and you're looking at what that device gets, at true size. Change the curve in
`Responsive.luau` and the story shows the result without a device.
