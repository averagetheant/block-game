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
   the id you already hold takes the vote back, so there's no un-vote button.
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

None. Panel icons are `rbxassetid://` literals on the registered modes, and the
voters are `rbxthumb://` headshots Roblox resolves without a web call from us.

## Packets

`GamemodeVote` namespace (ByteNet):

| Packet | Direction | Payload |
| ------ | --------- | ------- |
| `Cast` | Client → Server | `{ optionId }`. Sending the id you already hold takes the vote back. Unknown ids, and votes cast outside an open poll, are dropped server-side. |
| `State` | Server → All | `{ endsAt, winnerId, options, voters }`. Sent on change, not on a tick. |

`endsAt` is a `workspace:GetServerTimeNow()` stamp, so clients run the clock
locally instead of us shipping a packet a second. It doubles as the "a vote is
up" flag — **0 means closed**, and that's what the client keys its frame off. It
stays at its (now past) value through the result window so the winner has a
moment on screen.

`voters` is who voted for what, not a count, because the screen shows a vote as
that player's headshot.

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

GamemodeVote names neither TowerGame nor any other feature.

## Constants worth knowing

`GamemodeVote.Constants` (`src/features/GamemodeVote/Constants.luau`):

| Key | Default | What it controls |
| --- | ------- | ---------------- |
| `VOTE_SECONDS` | `15` | How long the poll is open. Short on purpose — everything else is parked while it runs. |
| `RESULT_SECONDS` | `3` | How long the winner stays up before the frame closes. |
| `FRAME_ID` | `"GamemodeVote"` | The UIShell frame id the screen opens itself on. |

## Priority

`GamemodeVoteService.Priority = 5` — no dependency on another service's startup;
the vote does nothing until something calls `startVote()`.

## Not built yet

- **Ties are broken at random**, silently. The screen shows the winner as if it
  had won outright.
- **A vote nobody votes in picks at random**, so the caller always gets a mode
  back and never has to carry a "what if they all abstained" branch. Nothing
  says so on screen.
- The panel count is whatever's registered. Three fits the row; more would need
  the row to wrap or scroll.
