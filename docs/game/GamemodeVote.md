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
   `TowerService`, from one of two places, both of which park the game first
   (`intermission`: the turn queue stops, the storm clock is frozen, the height
   poll is off) so the vote has the board to itself and isn't a screen over a game
   still running underneath it:
   - `runRoundBreak`, right after the storm has taken the tower and ended a round;
   - `runOpeningVote`, once at server start, as soon as there is one player to vote
     — the session's **first** round is voted for like every other one rather than
     being the un-voted default nobody picked.
2. The server broadcasts the ballot and a deadline stamp. Every client's
   `GamemodeVoteView` sees `endsAt ~= 0` and opens the UIShell frame — which is
   what gives the vote the single-frame invariant (it takes over from whatever
   window the player had up) and the blur + FOV focus effect, for free.

   **It reclaims the shell for as long as the poll runs.** The shell holds one
   open frame, so opening another window over a live ballot — Daily Rewards off
   the topbar, anything off the sidebar — swaps the ballot out for it, and closing
   *that* window left the shell empty with the poll still running: the view had no
   reason to re-open (`active` hadn't changed), so the player watched the rest of
   the poll go by with no ballot on screen and the round's rules were decided
   without them. The effect now also watches `openFrameId` and re-opens the ballot
   whenever the shell goes empty mid-poll — but only when it's *empty*. A player
   may go and look at their rewards during a poll; a ballot that shoved itself
   back on top the moment anything else opened would be a fight rather than a
   takeover.
3. Players click panels for `VOTE_SECONDS` (15). A click sends the id. A
   vote lands as a **stamp**: the voter's headshot slams down from oversized to
   full at a hashed position and slight tilt, so a popular panel visibly piles
   up. The hash is off the user id — stable across re-renders (a `math.random`
   in the render body would re-scatter every stamp each time anyone voted) and
   identical on every client.

   **A vote can be moved but never taken back.** Pressing the panel you already
   hold used to clear the vote, which made the ballot's most obvious gesture —
   press the thing you want, press it again because it felt good — quietly
   destructive: a player could finish a poll having voted for nothing without
   meaning to, and no affordance on the screen says so. Now every press ends with
   your stamp on the panel you pressed; a repeat press just lands it again.

   That repeat is the one press with nothing else to show for it — same panel,
   same position, same weight — so the slam *is* the feedback, and it needs the
   wire to carry something. Each voter has a **press count** (`stamps`), bumped
   per accepted cast and read only as an identity: the controller plays the thud
   when a voter's `(optionId, stamps)` pair changes, and `Avatar` re-arms and
   replays its slam when the count changes under it. Nothing tallies it — one
   player is one vote however many times they press. The weight is also re-read on
   every press, which is what makes "buy the 2x pass mid-poll, press your pick
   again, it counts double" work without voting away and back.
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

A poll shows `BALLOT_SIZE` (4) panels, not every registered mode:

- every mode with **`pinned = true`** is always on it;
- the remaining slots are filled at random from the rest, **re-rolled per vote**.

So registering a tenth gamemode makes the ballot more varied rather than wider —
four panels is what fits a phone in landscape (`PANEL_WIDTH` × 4 plus gaps ≈
1005 canvas units, inside the 1280 reference), and a wall of options is a worse
choice than a short one. Five (≈1260) is where the row runs out of reference.

`PANEL_WIDTH` is `240`, not the `190` it started at: at the body tier a 190-wide
panel fits about ten characters a line, so every blurb in TowerGame's ballot
needed three or four lines to say itself and was given two. A name and a blurb
that a registering feature wrote are copy the panel has to hold, not text to
shrink — so the panel grew instead. Both labels wrap, both size their box as
`tier * rows + slack`, and both carry `fit` as the device backstop (see
[layout-surfaces.md](layout-surfaces.md) § Fitting text on a real device).

`pinned` exists for the "leave it alone" option a poll needs: a ballot of nothing
but twists gives the players no way to decline one. GamemodeVote doesn't know or
care *which* modes those are — the registering feature says so, and this feature
still names nobody.

**TowerGame pins two of the four**: Classic at `order` 0 and PVP at 1, so the
game's two actual ways to play are always the left-hand pair and the two rolled
twists are always the right-hand pair. Two rolled slots rather than one is
deliberate — with one, a ballot was "this twist, or not", and the answer to a
single twist is mostly "not". A mode players ask for by name (PVP) also can't be
left to the roll: at two slots out of five twists it would have been on about two
ballots in five.

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
incoming `voters` list against the last packet's, remembering each voter's
`(optionId, stamps)` pair — a change to either half is a stamp landing, which
covers a first vote, a move, and a repeat press of the panel already held. Doing
it in the render body instead would replay the cue on any unrelated re-render.
Three cases the diff has to get right:

- **Joining mid-vote.** The first packet of a poll you haven't seen is absorbed
  silently, or arriving would open with a burst of stamps for votes cast before
  you got there. Tracked by comparing `endsAt` against the poll last stamped.
- **Several votes in one packet** fire the cue **once**. Votes arrive one at a
  time in practice, and firing per-voter on the packet where several don't reads
  as a stutter rather than as several people voting.
- **A voter leaving the server** is now the only way a stamp comes off the board
  mid-poll (a vote can't be taken back). Their record is dropped from the seen-set
  rather than left behind, so a re-join can't look like a stamp that never moved.

## Packets

`GamemodeVote` namespace (ByteNet):

| Packet | Direction | Payload |
| ------ | --------- | ------- |
| `Cast` | Client → Server | `{ optionId }`. Sending the id you already hold re-stamps it; a vote is never taken back. Unknown ids, and votes cast outside an open poll, are dropped server-side. |
| `State` | Server → All | `{ endsAt, winnerId, options, voters }`. Sent on change, not on a tick. Each voter is `{ userId, optionId, weight, stamps }` — `stamps` being the press count that makes a repeat press a different packet from the one before it. |

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
sitting on a panel. It's re-read on *every* press, though, so the fix is to press
your pick again — you no longer have to vote away and back to reweigh it, because
pressing the panel you hold is a re-stamp rather than an un-vote.

## The screen

`GamemodeVoteUI.ui.luau` — one `ui.Panel` per mode in a `ui.Row` (icon, name,
blurb), each in a fixed `ui.Slot`, with the clock as a `ui.Text` **outside and
below** the row. No window chrome.

A vote reads as presence rather than a number: the voter's headshot lands in a
row along the panel's bottom margin, which the body stack leaves clear so a
filling panel never shifts the icon or the name. A transparent `TextButton` over
each panel is the hit area — it's removed once the poll resolves, so a late
click can't land on a closed vote. Once there's a winner the other panels fade
back and the caption becomes the winner's name.

**The panel under the pointer lifts.** It's the kit's `useHoverScale` on the same
`TextButton`, so a vote panel answers the pointer the way every other clickable in
the game does — including the hover and click cues. Two things are tuned down from
the kit's defaults, because a panel is not a button: `HOVER_SCALE` is 1.03 against
`theme.hoverScale`'s 1.06 (6% of a 240×370 panel is a shove, not a lift), and the
glass goes to `HOVER_TRANSPARENCY` (0.72) against its 0.8 default — the same axis
`LOST_TRANSPARENCY` (0.92) already uses, so the three states read as out, in, and
about to be picked. `PRESS_SCALE` (0.98) is the moment before the stamp lands.

**A `ui.Slot` holds each panel's place in the row.** A `UIScale` changes
`AbsoluteSize`, not just what's drawn, so a panel scaled inside the `ui.Row` would
push its neighbours apart and set the whole ballot breathing as the pointer
crossed it. The slot is fixed at `PANEL_WIDTH` × `PANEL_HEIGHT` and is what the row
measures; the panel lifts inside it, overhanging by three or four pixels into the
row's 15px gap, and takes `zIndex` 2 while hovered so it sits over its neighbours.

A resolved poll unmounts the hit area, and a GuiObject destroyed under the pointer
never fires `MouseLeave` — so `OptionPanel` releases the hover itself when `locked`
flips, guarded on actually being hovered so the result doesn't fire the whole
ballot's worth of hover-out cues on one frame.

The component is dumb (see [headless-core.md](headless-core.md)): it takes the
ballot, who voted for what, a clock, and the per-voter press counts, and calls
`onVote` with an id. Stamps are keyed by user id so somebody else voting doesn't
re-slam the whole wall; a move to another panel is a real unmount and slams on its
own; a repeat press changes only `voteStamps`, which `Avatar` watches to re-arm
and replay its own slam. Iterate it in the `GamemodeVoteUI` story, which drives
the real component off the real registry — clicking one panel twice there is the
repeat-press case, and the story mirrors the server by counting every click.

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
| `BALLOT_SIZE` | `4` | Panels per ballot. Every `pinned` mode is always on it; the rest are rolled at random per vote. TowerGame pins two (Classic, PVP), so two slots roll. |
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
