# Analytics

Funnels, economy events and progression events, reported to Roblox's
`AnalyticsService` and read on the Creator Dashboard.

Analytics owns no journeys. A feature declares the funnels it cares about in a
sibling `Analytics.luau` and fires their steps from its own code — the same
convention `PlayerData.luau` / `Settings.luau` / `Store.luau` / `Sidebar.luau` /
`Gamemode.luau` / `DailyRewards.luau` use. So `src/features/Analytics/` names no
other feature, and "what a conversion looks like" lives with the feature being
converted.

## Studio assets

None. Nothing has to be configured on the place either — funnels appear on the
dashboard the first time they receive an event, and there is no ID to allocate
the way there is for a developer product.

## The platform limits that shaped this

These are Roblox's, not ours, and exceeding one **does not error** — it silently
drops data, which is the worst failure mode telemetry can have. `Registry` warns
at registration time so a mistake is a load-time warn rather than a month of
missing numbers.

| Limit | Value | Where it's enforced |
| ----- | ----- | ------------------- |
| Unique funnels per experience | **10** | `Registry.registerFunnel` warns on the 11th |
| Steps per funnel | 1–100 | `Registry.registerFunnel` warns |
| Custom fields per event | 3 (`CustomField01..03`) | `AnalyticsService.fields` drops the rest |
| Unique custom-field combinations | 8,000 | Keep fields low-cardinality — never a user id |
| Unique currency types | 5 | We use one, `coins` |
| Unique transaction types | 20 | Six, in `Constants.TRANSACTION` |
| Unique item SKUs | 100 | Pack ids and product names |

**Ten funnels is the whole budget, and all ten are spent.** Adding an eleventh
means retiring one. The onboarding funnel is *not* one of the ten — it's a
separate API with its own dashboard tab.

All analytics methods are **server-only**. That's why client-side steps are
relayed through `Packets` rather than logged where they happen.

## The ten funnels

| id | Dashboard name | Owner | One session is | Steps |
| -- | -------------- | ----- | -------------- | ----- |
| `session` | Play Session | Analytics | one visit | Joined → 1 → 5 → 15 → 30 → 60 Minutes |
| `round` | Round Progress | TowerGame | one run | Round Started → First Piece Placed → Checkpoint 1/2/3/5/10 |
| `stage` | Stage Attempt | TowerGame | one checkpoint attempt | Stage Started → 25/50/75% Height → Cleared |
| `turn` | Turn Taken | TowerGame | one piece (**sampled 10%**) | Piece Received → Steered → Rotated → Dropped → Settled On Tower |
| `shop` | Shop Purchase | Store | one visit to the shop | Shop Opened → Tab Viewed → Pack Selected → Purchase Sent → Pack Granted |
| `product` | Robux Product | Store | one visit to the shop | Product Shown → Prompt Requested → Prompt Closed → Receipt Granted |
| `gamepass` | Gamepass Purchase | Store | one visit to the shop | Gamepass Shown → Prompt Requested → Prompt Closed → Pass Owned |
| `inventory` | Equip Flow | Store | one visit to the inventory | Inventory Opened → Tab Viewed → Pack Equipped |
| `daily` | Daily Rewards | DailyRewards | **one run, spanning days** | Reward Available → Window Opened → Day 1–6 Claimed → Grand Prize Claimed |
| `vote` | Gamemode Vote | GamemodeVote | one poll | Vote Opened → Ballot Shown → Vote Cast → Result Shown → Round Started |

### Why some of these are separate funnels

`shop`, `product` and `gamepass` could be one "purchase" funnel, and collapsing
them would free two slots. They're kept apart because the only comparison worth
making is between them: a shop funnel that converts next to a product funnel
that doesn't means the **prices** are wrong, while both failing at the same step
means the **card** is. Averaged together, neither is visible.

`inventory` earns its slot on the same logic — an unequipped purchase is the
clearest refund-risk signal there is, and no purchase funnel can show it.

## The onboarding funnel

One funnel for the whole experience, fired at most **once per user ever**, on
its own API and its own dashboard tab. The step numbers are therefore a shared
space across features, and this table is the allocation:

| Step | Name | Registered in |
| ---- | ---- | ------------- |
| 1 | Joined | `Analytics/init.luau` |
| 2 | First Turn | `TowerGame/Analytics.luau` |
| 3 | First Block Placed | `TowerGame/Analytics.luau` |
| 4 | First Checkpoint | `TowerGame/Analytics.luau` |
| 5 | Shop Opened | `Store/Analytics.luau` |
| 6 | First Pack Owned | `Store/Analytics.luau` |

New steps go **on the end**. Registering a number twice warns at load.

Nothing on Roblox's side dedupes this funnel, so the high-water mark is
persisted at `profile.Analytics.Onboarding` (see `Analytics/PlayerData.luau`).
Firing step 3 on every drop is correct and cheap: it's counted once, forever.

## Adding a funnel to a feature

Drop `src/features/<Name>/Analytics.luau`:

```lua
return function(Analytics)
    Analytics.registerFunnel({
        id = "petHatch",
        name = "Pet Hatch",
        scope = "One egg.",
        steps = { "Egg Opened", "Hatch Started", "Pet Received" },
    })
end
```

Then fire the steps from the feature's own code:

```lua
-- server
local AnalyticsService = require(ServerScriptService.Features.Analytics.AnalyticsService)
AnalyticsService.start(player, "petHatch", "Egg Opened")   -- opens a session
AnalyticsService.step(player, "petHatch", "Pet Received")  -- continues it

-- client (relayed; Roblox's API is server-only)
local AnalyticsController = require(script.Parent.Parent.Analytics.AnalyticsController)
AnalyticsController.step("petHatch", "Egg Opened")
```

**Remember the ten-funnel cap.** Registering an eleventh warns loudly and Roblox
ignores it.

Steps are referenced **by name**, and the number Roblox receives is the index in
`steps`. That means inserting a step in the middle renumbers the rest
automatically and no call site changes — but it also renumbers them *on the
dashboard*, orphaning the history. In practice `steps` is append-only once a
funnel is live.

## Sessions, sampling and dedupe

A **funnel session** is one pass through a funnel, and it's what makes two visits
to the shop two rows instead of one row with doubled steps.

- `start(player, funnel, step)` opens a fresh session and logs its first step.
- `step(player, funnel, step)` continues the open one, opening one if there
  isn't one (a funnel whose first step was missed is still worth having).
- `startSession(player, funnel, id)` takes an explicit id, for funnels that
  outlive a server session. `daily` is the only one: a seven-day run is keyed
  `<userId>-<runStartDate>` so all seven days land in one row.

Three rules the implementation leans on, all in `AnalyticsService`:

1. **Dedupe is per session, not per call.** A step reached twice counts once.
   This is what makes `step` safe to call from a hot path — the aim stream runs
   at 30 Hz and calls it on every packet.
2. **Sampling is decided once per session.** A per-step coin flip on the
   10%-sampled `turn` funnel would keep step 2 and drop step 3 of the same
   session, and the dashboard would read that as players abandoning at step 3.
3. **The rate budget is spent last.** `MAX_EVENTS_PER_MINUTE` (120/player) is
   charged immediately before logging, never as a guard at the top — otherwise
   one player aiming would drain the minute's allowance in four seconds and
   every real event behind it would be dropped.

## Economy events

Every coin that moves is logged with the balance *after* the move.

| Where | Flow | Transaction | SKU |
| ----- | ---- | ----------- | --- |
| `CashService.award` — zone bonus | source | Gameplay | `Zone` |
| `CashService.award` — height gained | source | Gameplay | `Height` |
| `CashService.award` — idle tick | source | Gameplay | `Idle` |
| `CashService.award` — Cmdr `givecash` | source | Gameplay | `Admin` |
| `StoreService.processReceipt` — coin bundle | source | IAP | product name |
| `StoreService.onPurchase` — pack bought | sink | Shop | pack id |

Coins bought with Robux deliberately do **not** go through `CashService`: they're
a purchase, not earnings, and lumping them into the gameplay taps would make the
earn curve look twice as generous as it is. The 2× Cash gamepass multiplier *is*
included — the dashboard should show what actually entered the economy.

`source` is a plain string and Roblox counts 100 unique SKUs per experience, so
these stay a handful of literals. Never a player name or a round number.

## Progression events

Checkpoints are the game's levels, on one path (`TowerClimb`):

- **Start** — a round begins, at level 1.
- **Complete** — a checkpoint cleared, at its number.
- **Fail** — the storm took the tower, at the checkpoint they were reaching for.

Reported for **everyone in the server**, including spectators: one tower, one
climb. Deliberately not just the turn queue — a player with "Not playing" on is
still watching, and dropping them would quietly turn every round statistic into
a survey of active builders only.

## Switching it off

`Constants.Presentations`:

- `service = false` — nothing leaves the server. Every `AnalyticsService.*` call
  becomes a no-op and the call sites stay exactly where they are.
- `client = false` — client-reported steps are ignored. Server-side steps still
  log, so the funnels that are wholly server-driven (`round`, `stage`, `turn`,
  `vote`) keep working and the ones with a client first step lose their
  denominator.

## Files

| File | Realm | Role |
| ---- | ----- | ---- |
| `init.luau` | both | Public surface, the `session` funnel, auto-discovery, seal |
| `Constants.luau` | both | Platform limits, sample rates, transaction types |
| `Registry.luau` | both | Funnel + onboarding-step definitions, name→number resolution |
| `Packets.luau` | both | Client → server step relay |
| `PlayerData.luau` | both | `profile.Analytics.Onboarding` high-water mark |
| `AnalyticsService.server.luau` | server | The only caller of Roblox's `AnalyticsService` |
| `AnalyticsController.client.luau` | client | Fire-and-forget relay |

## Gotchas

- **The registry seals after discovery.** Registering a funnel later errors —
  the client would report steps a server that never heard of them would drop.
- **Both realms must register the same set.** That's automatic if the funnel
  lives in a sibling `Analytics.luau`, which is the point of the convention.
- **Studio play-tests log nothing useful.** Events fire and are accepted, but
  the dashboard only aggregates from published places. The warns in the output
  are the signal that wiring is correct.
- **Custom fields are low-cardinality or they're useless.** Block type name and
  pack id are fine; a user id burns the 8,000-combination budget in an
  afternoon.
- **A feature that fires steps requires `Features.Analytics`**, the same way it
  requires `PlayerDataService`. Removing the Analytics feature means removing
  those call sites too — they are not soft references.
