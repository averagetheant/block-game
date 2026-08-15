# GamemodeVote

The between-rounds poll. A handful of panels, one vote per player, a clock, and a
winner handed back to whoever asked for the vote.

The feature owns the **mechanism** and no content: it has no gamemodes of its
own and never names another feature. TowerGame registers the modes it
implements, and TowerGame is what calls for a vote. Remove TowerGame and the
ballot is empty; remove GamemodeVote and TowerGame stops asking (see
[the dependency](#the-dependency) — that one is a hard require).

## The loop

1. Something calls `GamemodeVoteService.startVote()`. In game that's
   `TowerService.runRoundBreak`, right after the storm has taken the tower and
   ended the round — the turn queue is parked, the storm clock is frozen and the
   height poll is off (`intermission`), so the vote has the board to itself and
   isn't a screen over a game still running underneath it.
2. The server broadcasts the ballot and a deadline stamp. Every client's
   `GamemodeVoteView` sees `endsAt ~= 0` and opens the UIShell frame — which is
   what gives the vote the single-frame invariant (it takes over from whatever
   window the player had up) and the blur + FOV focus effect, for free.
3. Players click panels for `VOTE_SECONDS` (15). A click sends the id; clicking
   the id you already hold takes the vote back, so there's no un-vote button. A
   vote lands as a **stamp**: the voter's headshot slams down from oversized to
   full at a hashed position and slight tilt, so a popular panel visibly piles
   up. The hash is off the user id — stable across re-renders (a `math.random`
   in the render body would re-scatter every stamp each time anyone voted) and
   identical on every client.
4. The clock ends, the server picks the winner, and it stays on screen for
   `RESULT_SECONDS` (3) before the frame closes.
5. `startVote()` returns the winning id to its caller, which does whatever that
   means for it.

`startVote()` **yields** for the whole poll. That's deliberate: the caller reads
as a step in a sequence ("wreck the tower, ask what's next, start the round")
rather than a callback dropped into the middle of one.

The winner applies to the **whole round** — every stage of it, across as many
checkpoints as the players clear. Clearing a checkpoint deliberately does *not*
re-vote: changing the rules out from under a run in progress is the thing this
placement avoids.

## Adding a gamemode

Drop a `Gamemode.luau` in **your own** feature folder — no edit in
`src/features/GamemodeVote/`:

```lua
-- src/features/MyFeature/Gamemode.luau
return function(GamemodeVote)
    GamemodeVote.register({
        id = "lowGravity",
        name = "Moon Shot",
        blurb = "Gravity's off.",
        icon = "rbxassetid://…",
        order = 4,
        -- Opaque to GamemodeVote. Your feature reads it back when it wins.
        modifier = { gravity = 40 },
    })
end
```

The registry auto-discovers the file the same way PlayerData discovers
`PlayerData.luau` and Settings discovers `Settings.luau`. The module returns a
*function* rather than requiring GamemodeVote directly, which is what keeps a
registering feature from closing a require cycle.

`modifier` is never read here. It's a payload the registering feature hands
itself back, so a new kind of modifier needs no change in this folder.

### The ballot

A poll shows `BALLOT_SIZE` (3) panels, not every registered mode:

- every mode with **`pinned = true`** is always on it;
- the remaining slots are filled at random from the rest, **re-rolled per vote**.

So registering a tenth gamemode makes the ballot more varied rather than wider —
three panels is what fits a phone in landscape, and a wall of options is a worse
choice than a short one.

`pinned` exists for the "leave it alone" option a poll needs: a ballot of nothing
but twists gives the players no way to decline one. GamemodeVote doesn't know or
care *which* mode that is — the registering feature says so, and this feature
still names nobody. (TowerGame pins Classic.)

The chosen set is sorted back into `order` before it goes out, so a pinned mode
sits where its `order` says rather than merely first-because-pinned.

**The discovery pass lives in `Registry.luau`, not `init.luau`** — unlike
PlayerData and Settings. The server entry script only loads `*Service` modules,
so a server-side consumer requires the registry and never the init; hanging
discovery off the init would leave the server's ballot empty while every
client's was full. The registry is also the realm-neutral half — the init
additionally pulls in the React UI, which the server has no use for.

## Presentations

| Kind | File | What it does |
| ---- | ---- | ------------ |
| Screen | `GamemodeVotePresentation.client.luau` | Registers `GamemodeVoteView` as a **root** (not a HUD window slot — nothing in the sidebar opens a vote). The container is always mounted and renders nothing until a poll arrives, then opens its own UIShell frame. |
| Command | `GamemodeVoteCommand.server.luau` | `startvote` opens a poll on demand. The natural trigger is the storm ending a round, minutes of play away; this gets the screen up in a second. |

Both route through `GamemodeVoteService.startVote`. Note that a vote started
from the command has **no consumer** — the winner comes back to the Cmdr console
and nothing applies it. Only TowerGame's round-break call feeds the result into a
round.

Gate either surface off in `Constants.Presentations`.

## Studio assets

| Path | What | If it's missing |
| ---- | ---- | --------------- |
| `Assets.Sounds.Stamp` | A short `Sound` — the thud a stamp makes | The stamps still land, silently |

Panel icons are `rbxassetid://` literals on the registered modes, and the voters
are `rbxthumb://` headshots Roblox resolves without a web call from us.

The cue is played through `Boil.audio.playCue` at `STAMP_VOLUME` (0.7) — quieter
than full, because on a busy server this can fire once per voter in quick
succession and at full weight it sounds like hail.

**The sound is fired from the controller, not the view.** `playStamps` diffs the
incoming `voters` list against the last packet's, which is exactly when the view
mounts a new stamp (it keys them by user id, so a voter moving to another panel
is a real unmount and does stamp again). Doing it in the render body instead
would replay the cue on any unrelated re-render. Three cases the diff has to get
right:

- **Joining mid-vote.** The first packet of a poll you haven't seen is absorbed
  silently, or arriving would open with a burst of stamps for votes cast before
  you got there. Tracked by comparing `endsAt` against the poll last stamped.
- **Several votes in one packet** fire the cue **once**. Votes arrive one at a
  time in practice, and firing per-voter on the packet where several don't reads
  as a stutter rather than as several people voting.
- **Taking a vote back** unmounts a stamp rather than landing one, so it's
  silent — but the voter has to be dropped from the seen-set, or re-voting for
  the same option afterwards would be silent too.

## Packets

`GamemodeVote` namespace (ByteNet):

| Packet | Direction | Payload |
| ------ | --------- | ------- |
| `Cast` | Client → Server | `{ optionId }`. Sending the id you already hold takes the vote back. Unknown ids, and votes cast outside an open poll, are dropped server-side. |
| `State` | Server → All | `{ endsAt, winnerId, options, voters }`. Sent on change, not on a tick. Each voter is `{ userId, optionId, weight }`. |

`endsAt` is a `workspace:GetServerTimeNow()` stamp, so clients run the clock
locally instead of us shipping a packet a second. It doubles as the "a vote is
up" flag — **0 means closed**, and that's what the client keys its frame off. It
stays at its (now past) value through the result window so the winner has a
moment on screen.

`voters` is who voted for what, not a count, because the screen shows a vote as
that player's headshot. `weight` rides along only so the screen can *say* a vote
counts double — the tally itself is the server's, and always was.

## 2x Votes

The gamepass (`Constants.GAMEPASS_DOUBLE_VOTE`, id `1948166343`) makes one
player's stamp count `DOUBLE_VOTE_WEIGHT` (2) in the tally. The card is
registered in this feature's `Store.luau`; ownership is read on the server with
`StoreService.ownsGamepass` when the vote is cast, never sent up by the client.

It's still **one stamp**. The row along the bottom of a panel shows who is on it,
and a second headshot for the same player would read as a second player — so the
stamp gets a small `x2` tag instead.

The weight is recorded **when the vote is cast**, not when the count runs, so
buying the pass mid-poll doesn't retroactively reweigh a stamp that's already
sitting on a panel. Re-vote and it counts double.

## The screen

`GamemodeVoteUI.ui.luau` — one `ui.Panel` per mode in a `ui.Row` (icon, name,
blurb), with the clock as a `ui.Text` **outside and below** the row. No window
chrome.

A vote reads as presence rather than a number: the voter's headshot lands in a
row along the panel's bottom margin, which the body stack leaves clear so a
filling panel never shifts the icon or the name. A transparent `TextButton` over
each panel is the hit area — it's removed once the poll resolves, so a late
click can't land on a closed vote. Once there's a winner the other panels fade
back and the caption becomes the winner's name.

The component is dumb (see [headless-core.md](headless-core.md)): it takes the
ballot, who voted for what, and a clock, and calls `onVote` with an id. Iterate
it in the `GamemodeVoteUI` story, which drives the real component off the real
registry.

## The dependency

TowerGame → GamemodeVote, one way, in two places:

- `TowerGame/Gamemode.luau` registers the modes (soft — auto-discovered, and
  inert if GamemodeVote isn't installed).
- `TowerService` **hard-requires** `GamemodeVoteService` to call `startVote()`
  in the round break. Removing GamemodeVote without removing that call breaks
  TowerGame, the same way removing PlayerData would break Notes.

FavouritePrompt → GamemodeVote is the other one: its controller watches this
feature's client store for a ballot opening, because that's the beat it wants to
ask a first-time player to favourite the game on. Also one-way, also invisible
from here — see [FavouritePrompt.md](FavouritePrompt.md).

GamemodeVote names TowerGame nowhere. It does name **Store**, in two places, and
both are about the 2x Votes gamepass:

- `GamemodeVote/Store.luau` registers the card (soft — auto-discovered by Store,
  and never required by this feature itself).
- `GamemodeVoteService` **hard-requires** `StoreService` to ask whether a voter
  owns the pass. Uninstall Store and this require has to go with it, along with
  `weightOf` — every vote then weighs 1, which is what it weighed before.

## Constants worth knowing

`GamemodeVote.Constants` (`src/features/GamemodeVote/Constants.luau`):

| Key | Default | What it controls |
| --- | ------- | ---------------- |
| `VOTE_SECONDS` | `15` | How long the poll is open. Short on purpose — everything else is parked while it runs. |
| `BALLOT_SIZE` | `3` | Panels per ballot. Every `pinned` mode is always on it; the rest are rolled at random per vote. |
| `RESULT_SECONDS` | `3` | How long the winner stays up before the frame closes. |
| `FRAME_ID` | `"GamemodeVote"` | The UIShell frame id the screen opens itself on. |
| `GAMEPASS_DOUBLE_VOTE` | `1948166343` | The 2x Votes gamepass. Must exist on the place. |
| `DOUBLE_VOTE_WEIGHT` | `2` | What that pass makes one stamp count for. |

## Priority

`GamemodeVoteService.Priority = 5` — no dependency on another service's startup;
the vote does nothing until something calls `startVote()`. It starts *ahead* of
Store (10) and that's fine: the only thing it asks Store is whether a voter owns
2x Votes, and the first poll is a whole storm stage away.

## Not built yet

- **Ties are broken at random**, silently. The screen shows the winner as if it
  had won outright.
- **A vote nobody votes in picks at random**, so the caller always gets a mode
  back and never has to carry a "what if they all abstained" branch. Nothing
  says so on screen.
- The panel count is whatever's registered. Three fits the row; more would need
  the row to wrap or scroll.
