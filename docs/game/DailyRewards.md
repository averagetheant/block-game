# DailyRewards

Come back tomorrow, get the next thing. A run of seven days: claim one per UTC day to advance, miss more than the grace and the run starts over. The last day is the grand prize and gets a tall card beside the grid.

**The feature owns no rewards.** It ships the mechanism — the run, the streak, the claim gate, the window, the topbar button — and knows nothing about coins or packs. Features declare what they give and how to give it in a sibling `DailyRewards.luau`, the same convention PlayerData / Settings / Store / Sidebar / Gamemode use.

## What it does

- **Shared surface** (`init.luau`): `Constants`, `Cycle`, `Layout`, `UI`, `FRAME_ID`, and the registry passthroughs (`registerKind`, `registerDay`, `listDays`, `getDay`, `getKind`). Requiring it runs the auto-discovery pass and then **seals** the registry.
- **The run** (`Cycle.luau`): pure functions over a saved slice and a timestamp. Shared, so the client renders against exactly the arithmetic the server validates with — a card can't offer a day the server will refuse.
- **Persistence**: `{ Streak, LastClaim }` on the profile, registered in `PlayerData.luau`. Streak is written as *the day just granted*, so it wraps at 7 instead of growing forever.
- **Claiming** (`DailyRewardsService`): the only place a claim is judged. Grants first, records second.
- **Surfaces**: a TopbarPlus button, the window it opens, and two Cmdr commands.

## Day boundaries are UTC midnight, not "24h since your last claim"

A rolling 24-hour window punishes playing earlier in the day — claim at 9pm and tomorrow's reward isn't there at 9am — which teaches players to claim later and later each day until they lose the streak to a clock they were never shown. A calendar day makes "come back tomorrow" literally true.

`Constants.GRACE_DAYS = 1` is the normal rule (claim on consecutive days or start over). Raise it to forgive a lapse.

## Adding a reward type

Two things get registered, and they have different owners.

A **kind** is *how to hand something over*, owned by the feature that owns the thing:

```lua
-- src/features/Pets/DailyRewards.luau
return function(DailyRewards)
    DailyRewards.registerKind({
        id = "pet",
        grant = function(player, payload)
            -- This module loads on BOTH realms, so the server-realm require
            -- lives inside the grant, where only the server runs it. Same
            -- trick as a Cmdr `Run`.
            local ServerScriptService = game:GetService("ServerScriptService")
            local PetsService = require(ServerScriptService.Features.Pets.PetsService)
            return PetsService.grantPet(player, payload.petId)
        end,
    })
end
```

A **day** is *what slot N gives*, owned by the feature whose content it is:

```lua
    DailyRewards.registerDay({
        day = 5,
        kind = "pet",
        payload = { petId = "corgi" },   -- shape is the kind's business
        name = "Corgi",                  -- drawn over the card art
        icon = assets.Icons.friends,
        caption = "Grand prize",         -- grand card only
    })
```

Rules:

- **`grant` returns true only when the player actually received it.** False means "not now": the claim is refused and the day *stays open*. A grant that throws is caught and treated the same way. This is why the service grants before it records — a player who lost a reward to a bug can retry, whereas a burned streak day is unrecoverable.
- **Register only from the shared `DailyRewards.luau`.** The registry seals after discovery and a later `register*` is a hard error, because the server validates claims against this registry: a client-only day is a claim the server rejects, and a server-only one is invisible in the window.
- **The module must not require `Features.DailyRewards`** (circular). It receives the table as an argument.
- Two features registering the same day warns and the second wins, so a game can deliberately override a shipped day.
- `name` is short by necessity — it's overlaid on the card art at the Large tier inside ~180px.
- A day nothing registered is drawn as a locked `???` card rather than being skipped. A hole is a content bug worth seeing, and shortening the run would silently renumber every day after it.

## What ships registered

| Day | Reward | Kind | Registered by |
| --- | ------ | ---- | ------------- |
| 1 | 100 Coins | `currency` | `TowerGame/DailyRewards.luau` |
| 2 | 150 Coins | `currency` | TowerGame |
| 3 | 250 Coins | `currency` | TowerGame |
| 4 | Hearts Pack | `pack` | `Reactions/DailyRewards.luau` |
| 5 | 500 Coins | `currency` | TowerGame |
| 6 | 750 Coins | `currency` | TowerGame |
| 7 | Needoh Blocks | `pack` | TowerGame (grand prize) |

The two kinds are registered by `Store/DailyRewards.luau`, because Store owns crediting a balance (`StoreService.credit`) and marking a pack owned (`StoreService.grantPack`). Store doesn't own the coins — TowerGame does — which is why Store registers the kinds and TowerGame schedules the days.

**Both packs in the run are exclusive to it.** `reactions.hearts` and `skins.needoh` register with `forSale = false`: no shop card, and the server refuses to sell them ([Reward-only packs](Store.md#reward-only-packs)). They're still ordinary registered packs, which is what lets `grantPack` hand them over and the Inventory draw them once earned. A reward you could have bought on day one isn't a reason to come back on day seven.

## Studio assets it expects

None. The topbar icon and the window's title badge are both `Constants.ICON` (`rbxassetid://79189310973071`), an uploaded asset; reward art comes from `ui.assets.Icons`.

## Packets it speaks

| Packet | Direction | Payload | Notes |
| ------ | --------- | ------- | ----- |
| `Claim` | client → server | `{ day: uint8 }` | The server re-resolves the run and refuses if `day` isn't the one that's open. The day is sent even though the server could derive it: a window left open across a UTC midnight would otherwise claim a different day than the one whose button was pressed. |

The client applies nothing locally — the replica diff on `Streak` / `LastClaim` is what moves a card to Claimed.

## Presentations

Gated by `Constants.Presentations` (see [presentations.md](presentations.md)).

- **`topbar`** — `DailyRewardsTopbar.client.luau`, a TopbarPlus button. Renders nothing itself (TopbarPlus owns its own ScreenGui); it exists to tie the icon's lifetime and selected state to React and UIShell. Mounted as a UIRegistry **root** so it's always live and sits inside `FrameProvider`.
- **`window`** — `DailyRewardsWindow.client.luau`, a `UIShell.Frame` + `ui.Window` + the View. Also a root: most windows in this game are built by the Sidebar rail for rail entries, and this feature's entry point is the topbar, so it mounts its own chrome.
- **`command`** — `claimdaily` (routes to the same `DailyRewardsService.claim` the packet does) and `dailystatus` (read-only).

### Topbar ↔ frame sync

The icon and the frame are kept in step both ways: clicking the icon opens the frame, and closing the window with its X (or opening another frame) deselects the icon. Both handlers ignore any event whose `fromSource` isn't `"User"`, which is what stops two things from fighting:

- `"AutoDeselect"` — TopbarPlus deselects our icon when *another* topbar icon is selected. That icon's handler is already opening its own frame, and React state updates aren't synchronous, so an unguarded `close()` would land afterwards and shut the frame the player just opened.
- the sync effect itself — `select()` / `deselect()` re-fire these events, and without the guard the effect and the handlers would drive each other in a circle.

### The claimable notice

The topbar button wears a TopbarPlus **notice** whenever a reward is waiting — a run nobody is reminded about is a run only the players who needed reminding least come back to. The button resolves `Cycle.resolve` itself rather than waiting on the window: it's mounted for the whole session, and the window is the thing being advertised.

Two details do the work:

- **A clear signal we never fire.** `icon:notify()` left to itself clears the notice on the icon's own `deselected` event, so opening the window and closing it again *without claiming* would drop the badge while the reward was still sitting there. Passing a signal nothing fires leaves `icon:clearNotices()` as the only thing that can retire it, and that runs when `canClaim` goes false — which is the replica diff from the claim landing.
- **One timer aimed at UTC midnight.** Nothing writes to the profile at the day boundary, so `canClaim` flips there with no diff to announce it. The button schedules a single `task.delay(state.secondsUntilReset + 1)` rather than polling; the resulting re-render reschedules the next one. (The window's own one-second tick only runs while it's open.)

The notice effect clears before it notifies, so a re-run can't stack a second badge on a state that's still one waiting reward.

## Constants worth knowing

- `CYCLE_DAYS = 7` — length of the run. The grid derives its rows from this, so a longer week just lays out wider; `registerDay` rejects a day outside the range.
- `GRACE_DAYS = 1` — missed days that end a run.
- `SQUARE_SIZE` / `GRAND_WIDTH` — card geometry. `Layout.windowSize()` derives the window from them (matching `ui.Window`'s own asymmetric padding), so resizing a card moves the frame instead of putting a scrollbar on it.
- `Presentations` — flip a surface off without deleting code.

## UI Labs

`DailyRewardsUI.story.luau` mounts the real UI in a Window sized by the same `Layout`, with the run state built by hand from sliders — the interesting cases (mid-run, all claimed, a wrapped run) are three clicks apart there and three days apart in game. Days come from the live registry, so an unregistered slot shows as `???` exactly as it would in game.

## Verifying the real path

The arithmetic is unit-testable without a session (`Cycle.resolve` is pure). For the full loop, Play-test: click the topbar button, click Claim, and watch the balance move and the card flip to Claimed. `dailystatus` reports where the run stands, and `claimdaily` a second time should refuse with the countdown.
