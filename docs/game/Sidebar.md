# Sidebar

The left rail: a vertical column of clickable icons, and the UIShell frames they
open. It's the game's primary navigation surface.

**Nothing edits this feature to get onto it.** Sidebar owns the mechanism; every
entry is owned by whichever feature put it there, via a registration API — see
[The registry](#the-registry) below. `Sidebar.UI` (the raw column) and
`Sidebar.Item` are still exported for when you want an icon column somewhere
that isn't the rail.

A vertical column of clickable icons. Each entry is **just the icon image**,
with its label overlaid inside the bottom of the icon — no gem background,
no panel chrome, no drop-shadow. Designed to live at the edge of the screen
and act as the primary navigation surface (open Inventory, Shop, Settings,
etc.). Wraps cleanly inside `UIShell.HideWhenFrameOpen` so it slides off
when any frame is open.

The label uses plain `ui.Text` (no `shadow`) with a Miter UIStroke for
contrast — same outline as the gem ShadowText, just without the offset
shadow layer. Weight is `Heavy`. If a chosen icon has a busy bottom edge
that swallows the label, prefer iterating the icon over re-adding shadow.

Hover behavior: the whole entry scales up (`useHoverScale`), and the **icon
only** tilts on hover. The tilt magnitude is rolled once at mount (random in
`[HOVER_TILT_MIN_DEG, HOVER_TILT_MAX_DEG]`, sign 50/50) and reused for every
subsequent hover — each item has its own signature angle. The label stays
upright because rotation lives on an inner `ImageLabel`, not the outer
click target.

## Studio assets

None. Sidebar mounts inside the existing `BoilRoot` ScreenGui created in
`src/client/init.client.luau`.

Icon assets: each item needs an `icon` (rbxassetid://…) you upload yourself.
The boilerplate uses `rbxassetid://137349421699691` (the same placeholder as
UIShowcase) for the bundled items — swap them for your own art.

## Packets

None. State lives in whatever the entries' `onClick` handlers do (typically
`UIShell.useFrame().toggle(id)`, which the rail wires for you).

## The registry

`SidebarPresentation.client.luau` mounts `Sidebar.Rail` as a root element. The
rail reads `Sidebar.Registry` at render, so it names no feature — and the window
*contents* come from the screen registry (`UIRegistry.registerScreen`), so it
doesn't learn what's inside them either.

Entries land in one of two clusters, rendered as two columns with a wider gap
between them (`Constants.GROUP_GAP`):

- **`"menu"`** (default) — navigation. Clicking toggles a UIShell frame.
- **`"actions"`** — one-shot buttons. Clicking runs `onClick`.

The gap is what tells a player that *Nuke* is a different sort of thing from
*Shop*, without drawing a divider.

Who's on it, as shipped:

| Group | Order | Entry | Registered by |
| ----- | ----- | ----- | ------------- |
| menu | 1 | Shop | `Store/Sidebar.luau` |
| menu | 2 | Bag | `Store/Sidebar.luau` |
| menu | 3 | Settings | `Settings/Sidebar.luau` |
| actions | 1 | Nuke | `TowerGame/TowerProductsPresentation.client.luau` |
| actions | 2 | Skip | `TowerGame/TowerProductsPresentation.client.luau` |

### Declarative entries (both realms)

Drop a `Sidebar.luau` next to your feature's `init.luau`:

```lua
-- src/features/Store/Sidebar.luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local assets = require(ReplicatedStorage.Shared.Boil).assets

return function(Sidebar)
    Sidebar.registerEntry({
        id = "Shop", label = "Shop",
        icon = assets.Icons.shoppingBasket,
        frameId = "Shop",           -- the UIShell frame this opens
        titleVariant = "yellow",    -- colors the Window's title badge
        order = 1,
    })
end
```

The rail renders `<UIShell.Frame id=frameId>` + `<ui.Window>` for you and fills
it from `UIRegistry.getScreens()[frameId]`. An entry with no registered content
still opens — an empty window is a truer signal than a silent button that the
feature forgot its `registerScreen`.

### Client-only entries

When the click needs client code (prompting a Robux purchase, calling a
controller), register from a `*Presentation.client.luau` instead — a shared
`Sidebar.luau` would drag `MarketplaceService` onto the server:

```lua
-- src/features/TowerGame/TowerProductsPresentation.client.luau
Sidebar.registerEntry({
    id = "TowerNuke", label = "Nuke",
    icon = Constants.CASH_IMAGE,
    group = "actions", order = 1,
    onClick = function()
        StoreController.promptProduct(Constants.PRODUCTS.NUKE)
    end,
})
```

Unlike the Settings registry this one is deliberately **not sealed** after
discovery: the client-realm route above is a legitimate second window, and
nothing on the server reads it (the server never renders a sidebar), so the two
realms disagreeing is harmless.

### Entry fields

| Key | Type | Notes |
| --- | ---- | ----- |
| `id` | `string` | React key. Unique across the rail. |
| `icon` / `label` | `string` | Drawn by `SidebarItem` — label overlaid inside the icon. |
| `order` | `number?` | Sort within the group. Ties break by label. |
| `group` | `"menu" \| "actions"?` | Defaults to `"menu"`. |
| `frameId` | `string?` | UIShell frame to toggle. Defaults to `id` unless `onClick` is set. |
| `windowTitle` / `titleVariant` / `windowSize` | — | Window chrome. Title defaults to `label`. |
| `onClick` | `(() -> ())?` | Runs instead of opening a frame. Set one or the other, not both. |

## Public API

```lua
local Sidebar = require(ReplicatedStorage.Features.Sidebar)
```

### `<Sidebar.UI items={…}>`

```lua
React.createElement(Sidebar.UI, {
    items = {
        { id = "Inventory", icon = "rbxassetid://…", label = "Inventory",
          onClick = function() ... end },
        { id = "Shop",      icon = "rbxassetid://…", label = "Shop",
          onClick = function() ... end },
    },
    iconSize  = 72,                       -- optional, square item size (px)
    labelSize = 32,                       -- optional, label TextSize
    spacing   = 12,                       -- optional, gap between items
    padding   = 12,                       -- optional, outer padding
    position  = UDim2.fromScale(0, 0.5),  -- defaults to left-center
    anchorPoint = Vector2.new(0, 0.5),
})
```

Each item:

| Key       | Type             | Notes                                                          |
| --------- | ---------------- | -------------------------------------------------------------- |
| `id`      | `string`         | React child key. Must be unique across the items list.         |
| `icon`    | `string`         | `rbxassetid://…` image. Drawn `ScaleType = Fit`.               |
| `label`   | `string`         | Plain text overlaid at the bottom-inside of the icon.          |
| `onClick` | `(() -> ())?`    | Fired on Activated. `nil` makes the item visually inert.       |

The container auto-sizes vertically — height follows item count. Width is
fixed by `iconSize + 2 * padding`.

### `<Sidebar.Item>`

The single-entry component, exported for when you need to drop an icon+label
into a layout that isn't a Sidebar column.

```lua
React.createElement(Sidebar.Item, {
    icon = "rbxassetid://…",
    label = "Inventory",
    onClick = function() ... end,
})
```

## Constants worth knowing

`Sidebar.Constants` (`src/features/Sidebar/Constants.luau`):

| Key | Default | What it controls |
| --- | --- | --- |
| `DEFAULT_ICON_SIZE`      | `72` | Square item side length (px). |
| `DEFAULT_LABEL_SIZE`     | `theme.textSizeRegular` (`32`) | Label `TextSize` (px). The shared ladder's body tier — a phone halves it to ~16px, so this is the floor rather than a starting point. |
| `LABEL_STROKE_THICKNESS` | `2`  | Miter UIStroke thickness on the label. Set to `0` and update SidebarItem to drop the outline. |
| `LABEL_BOTTOM_INSET`     | `0`  | Pixels between the label's bottom edge and the icon's bottom edge — keeps the label inside the icon. `0` sits it flush with the icon's bottom edge, still inside the art's visual bounds. |
| `LABEL_BLEED`            | `40` | How far the label may run past each side of its icon (px). A nav word at the body tier is wider than a 72px square, so this is the declared box for that overflow: the label shrinks (`fit`) rather than grow past it, and `RAIL_MARGIN` is measured from it. |
| `HOVER_TILT_MIN_DEG`     | `4`  | Minimum random tilt magnitude applied to the icon on hover (degrees). |
| `HOVER_TILT_MAX_DEG`     | `12` | Maximum random tilt magnitude. Set to `0` (both) to disable the tilt entirely. |
| `ITEM_SPACING`       | `12` | Vertical gap between sibling items (px). |
| `PADDING`            | `12` | Outer Sidebar padding (px). |
| `GROUP_GAP`          | `28` | Gap between the "menu" and "actions" clusters. |
| `RAIL_MARGIN`        | `52` | Distance from the screen's left edge to the rail (px). Keep it ≥ `LABEL_BLEED`: at `20` the icons cleared the edge but every label wider than its icon hung off the side of the screen, worst on a phone where the margin is half as many device pixels and the display's rounded corners eat into it too. |
| `WINDOW_SIZE`        | `820×600` | Default size of the Window an entry opens. Override per entry with `windowSize`. |
| `Presentations.root` | `true` | The rail itself. Off = every registered entry goes away with it, code intact. |

## Priority

None — Sidebar has no `Service` / `Controller`. The rail is a root element
registered by `SidebarPresentation.client.luau`; no startup ordering applies.

## Wiring to UIShell

The rail does it for you. An entry with a `frameId` gets a
`<UIShell.Frame id=frameId>` wrapping a `<ui.Window>`, and the whole rail rides
inside `HideWhenFrameOpen` so it slides off-screen while any frame is up.

What a feature still owns is the window's *contents*, registered separately from
its own presentation:

```lua
-- src/features/Store/ShopPresentation.client.luau
UIRegistry.registerScreen(Constants.SHOP_FRAME_ID, React.createElement(ShopView))
```

Two registrations, on purpose: the rail entry is declarative and loads on both
realms, while the contents are a React element and can only exist on the client.
See `docs/game/UIShell.md` § "Adding a new frame" for the frame system itself.
