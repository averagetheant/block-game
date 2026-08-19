# DailyRewards

Come back tomorrow, get the next thing. A run of seven days: claim one per UTC day to advance, miss more than the grace and the run starts over. The last day is the grand prize and gets a tall card beside the grid.

**The feature owns no rewards.** It ships the mechanism — the run, the streak, the claim gate, the window, the topbar button — and knows nothing about coins or packs. Features declare what they give and how to give it in a sibling `DailyRewards.luau`, the same convention PlayerData / Settings / Store / Sidebar / Gamemode use.

## What it does

- **Shared surface** (`init.luau`): `Constants`, `Cycle`, `Layout`, `UI`, `FRAME_ID`, and the registry passthroughs (`registerKind`, `registerDay`, `listDays`, `getDay`, `getKind`). Requiring it runs the auto-discovery pass and then **seals** the registry.
- **The run** (`Cycle.luau`): pure functions over a saved slice and a timestamp. Shared, so the client renders against exactly the arithmetic the server validates with — a card can't offer a day the server will refuse.
- **Persistence**: `{ Streak, LastClaim }` on the profile, registered in `PlayerData.luau`. Streak is written as *the day just granted*, so it wraps at 7 instead of growing forever.
- **Claiming** (`DailyRewardsService`): the only place a claim is judged. Grants first, records second.
- **Surfaces**: a TopbarPlus button, the window it opens, the join prompt that
  opens it for you, and two Cmdr commands.

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
- **`window`** — `DailyRewardsWindow.client.luau`, a `UIShell.Frame` + `ui.Window` + the View, plus `DailyRewardsPrompt` (the scrim and the notice) beside it. Also a root: most windows in this game are built by the Sidebar rail for rail entries, and this feature's entry point is the topbar, so it mounts its own chrome — and its own layer.
- **`command`** — `claimdaily` (routes to the same `DailyRewardsService.claim` the packet does) and `dailystatus` (read-only).

### Topbar ↔ frame sync

The icon and the frame are kept in step both ways: clicking the icon opens the frame, and closing the window with its X (or opening another frame) deselects the icon. Both handlers ignore any event whose `fromSource` isn't `"User"`, which is what stops two things from fighting:

- `"AutoDeselect"` — TopbarPlus deselects our icon when *another* topbar icon is selected. That icon's handler is already opening its own frame, and React state updates aren't synchronous, so an unguarded `close()` would land afterwards and shut the frame the player just opened.
- the sync effect itself — `select()` / `deselect()` re-fire these events, and without the guard the effect and the handlers would drive each other in a circle.

### The join prompt

A badge on a topbar button is an invitation; this is a sentence. A run nobody is
walked through on their first day is a run only the players who needed it least
ever finish, and the whole point of a seven-day cycle is the seventh day.

`DailyRewardsPrompt` is the whole behaviour, and it plays by three rules:

- **Once per session, on join.** It fires the first time the profile lands with
  something claimable and never again. A player who closes the window has
  answered the question; one that reopened itself would be the game arguing.
  Nothing is decided before the replica arrives — `Cycle.resolve(nil, …)` reads as
  "never claimed, claim now", which is right for a new player and a lie for
  everybody else.
- **Everything else goes dark.** A scrim fades in behind the window at
  `SCRIM_TRANSPARENCY`, `Active = true` so it swallows clicks as well as light.
  That's the trick: a dimmed HUD you can still press is decoration, one you can't
  is an instruction. The only live controls left are the ones drawn above it —
  the Claim button and the window's X.
- **The scrim belongs to the prompt, not to the window.** Opening the same window
  yourself from the topbar darkens nothing: you chose to be there.

**It stays up while anything is still claimable.** Claiming with another reward
waiting leaves the scrim and the window exactly as they are, so the next card
lights up under the same dimmed screen and the player claims again. With today's
UTC-day rule at most one is ever waiting — but "how many" is `Cycle`'s answer, and
the prompt reads it rather than assuming.

**The claim is detected as `canClaim` going true → false**, never as "the button
was pressed". The claim is the server's to judge, so the replica diff is the only
event that means a reward actually changed hands — and it's the same event whether
the player pressed Claim, ran `claimdaily`, or was granted it some way that
doesn't exist yet.

Then the closing beat: the notice goes up, the window closes after
`CLOSE_SECONDS` (3), and the notice outlives it to `NOTICE_SECONDS` (5) — so the
last thing on the screen is *"Come back tomorrow for your next daily reward!"*,
which is the sentence the whole mechanism exists to make true. The window is only
closed if it is still the open frame; three seconds is long enough for the player
to have opened something else.

### Layering, and where the coins land

The window's root sits on `ui.layers.window` ([layout-surfaces](layout-surfaces.md#stacking-uilayers)),
which is what puts it over every HUD — before that it drew in root-registration
order and could come out behind the PVP standings board.

The scrim, the window and the notice share that one root because they stack on
either side of each other: scrim (`SCRIM_ZINDEX`) under the window
(`WINDOW_ZINDEX`) under the notice (`NOTICE_ZINDEX`). Only siblings sort against
each other, so the prompt returns its two halves as a **Fragment** and lets the
root do the sorting.

The payout animation is TowerGame's, not this feature's: claiming coins credits
the profile, `TowerFeedbackController` turns that diff into a signal, and
`CashFly` bursts a dozen bills at the counter. That burst starts in the middle of
the screen — behind an open window — which is why the counter now mounts on
`ui.layers.flourish` as its own root (`TowerCashView`) rather than inside the two
HUDs. The bills fly over the scrim and land on a counter that's still lit, while
the notice is up.

### The pulsing Claim button

The live day's button breathes: one TweenInfo with `RepeatCount = -1` and
`Reverses`, so the scale runs `1 → PULSE_SCALE → 1` forever with no per-frame work
and nothing to tear down by hand. When the day is claimed the target drops back to
1 and a short quad tween puts it there.

A dimmed screen points at that row, and a button sitting perfectly still in the
middle of it is one a new player reads as a label. The UIScale rides on a centred
inner slot — a UIScale transforms about its parent's AnchorPoint, and the row's
own top-left anchor would swell the button down and to the right instead of about
itself.

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
- `PULSE_SCALE` / `PULSE_SECONDS` — how far the live Claim button swells, and how
  long one breath takes.
- `SCRIM_TRANSPARENCY` / `SCRIM_FADE_SECONDS` — how dark the prompt makes the rest
  of the screen, and how quickly. Dark enough that the HUD reads as switched off,
  short of hiding it.
- `CLOSE_SECONDS` (3) / `NOTICE_SECONDS` (5) — how long the window stays up after
  the last reward is claimed, and how long the notice outlives it.
- `NOTICE_TEXT` — the sentence itself.
- `SCRIM_ZINDEX` / `WINDOW_ZINDEX` / `NOTICE_ZINDEX` — the stack inside the
  feature's own root. The root's own layer is `ui.layers.window`.
- `Presentations` — flip a surface off without deleting code.

## UI Labs

`PromptOverlay.story.luau` loops the join prompt's sequence — darken, claim, notice, close — at the shipped timings, against a stand-in window. In game that sequence needs a fresh join with a reward waiting, i.e. one look per UTC day.

`DailyRewardsUI.story.luau` mounts the real UI in a Window sized by the same `Layout`, with the run state built by hand from sliders — the interesting cases (mid-run, all claimed, a wrapped run) are three clicks apart there and three days apart in game. Days come from the live registry, so an unregistered slot shows as `???` exactly as it would in game.

## Verifying the real path

The arithmetic is unit-testable without a session (`Cycle.resolve` is pure). For the full loop, Play-test: click the topbar button, click Claim, and watch the balance move and the card flip to Claimed. `dailystatus` reports where the run stands, and `claimdaily` a second time should refuse with the countdown.
