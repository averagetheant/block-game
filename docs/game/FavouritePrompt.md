# FavouritePrompt

Asks a player to favourite the experience — once, ever, at the first gamemode
vote they see.

The whole feature is a *moment* and a flag. Roblox draws the prompt, the profile
remembers that it was drawn, and GamemodeVote supplies the beat to draw it on.
There is no UI here and no screen to open.

## The moment

The prompt fires on the **first ballot this player has ever seen open**, which
for a first-time player is the first round break after they join.

The join itself is the obvious alternative and it's the wrong one: a player who
has been in the game for eleven seconds has no opinion about it yet, and the
loading screen is the worst possible place to put a modal. The round break is the
one beat where nothing is being built, the tower they just played is still on
screen, and the game is already asking them a question.

A returning player who has never been asked (anyone who played before this
feature shipped) gets asked at their next vote. `Prompted` is a flag, not a
join counter — "first time" is expressed as "hasn't been asked yet", which is
the thing that actually matters.

### It lands on top of the ballot

`PROMPT_DELAY` is `0`, so the prompt goes up with the panels. Roblox's prompt is
**modal**, so a first-timer's first vote is largely spent on it — the poll only
runs for GamemodeVote's `VOTE_SECONDS` (15).

That's the trade the placement makes, and the knob to change it is one number:
set `PROMPT_DELAY` past `VOTE_SECONDS + RESULT_SECONDS` (18) and the ask happens
on the way into the round instead of over the ballot. The flag is claimed when
the prompt is *scheduled*, so a longer delay can't produce two asks.

## The flag

One profile field, `FavouritePrompt.Prompted`, registered through the usual
`PlayerData.luau` slice.

It records **the ask, not the answer**. Roblox reports how the prompt closed
(`PromptSetFavoriteCompleted` / `Enum.AvatarPromptResult`), but a "no" is still
an answer and asking again would be nagging — so declining costs the same one
ask that accepting does.

It's on the profile rather than in memory because "only once" means once per
*player*. A session-local guard would ask again on every rejoin, which is the
version of this that gets a game reported rather than favourited.

There is also a **session guard** in the controller, on top of the flag. The
profile write is a round trip away and `PROMPT_DELAY` can outlast a poll, so
between scheduling the prompt and the replica diff coming back there's a window
where the flag still reads `false` and another ballot could open in it.

The guard is dropped when the flag goes `true` → `false` under it — that's the
`favouriteprompt` command resetting it, and the reset would otherwise need a
rejoin to take effect. Watched as an *edge* rather than as "is it false now",
because any other profile write during that window would otherwise clear the
guard, which is the one thing it exists to prevent.

## Who decides

The client. `AvatarEditorService` is a client service, and "the ballot reached
this player's screen" is a client fact — the server opens a poll for a *server*,
not for a person, and the player mid-load or mid-teleport never sees it.

So the client watches `GamemodeVoteController.DataChanged` for the edge where
`endsAt` goes non-zero, checks its own replica, prompts, and reports. The server
half is one write.

That write is one-way — `false` → `true`, never back — which is why the packet
carries no payload and needs no rate limit: a client spamming it is asking to be
marked as prompted, which it already is. Nothing else on the profile is
reachable from it.

**A profile that hasn't arrived yet skips the poll** rather than guessing. It
only happens to someone who joined seconds before a round ended, and both wrong
guesses (asking a returning player again, spending the ask silently) are worse
than waiting for the next vote.

## The prompt

```lua
AvatarEditorService:PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset, true)
```

A place is an asset, so favouriting it is favouriting the experience.

The call **throws** rather than returning a result when the place can't be
favourited — an unpublished place in Studio is the one you'll hit — so it's
wrapped, and the report to the server only goes out if the prompt actually went
up. A throw would otherwise burn the player's one ask on a prompt they never
saw. The session guard stays set either way: whatever makes this fail is a
property of the place, not of the moment, so retrying at the next vote would
only warn again.

## Presentations

| Kind | File | What it does |
| ---- | ---- | ------------ |
| Command | `Commands.luau` | `favouriteprompt` (alias `favoriteprompt`) clears the flag on the executor, so the next vote asks again. |

No screen: the prompt *is* the screen and it's Roblox's. No world part: "would
you favourite this?" isn't a thing you walk up to.

The command is the only way to see this flow twice — it's keyed to the account,
and you don't get a fresh account per test run. Pair it with GamemodeVote's
`startvote` to go straight to the ask:

```
favouriteprompt
startvote
```

Gate it off in `Constants.Presentations`.

## Studio assets

None. Everything is code, and the prompt's art is the experience's own thumbnail,
fetched by Roblox.

## Packets

`FavouritePrompt` namespace (ByteNet):

| Packet | Direction | Payload |
| ------ | --------- | ------- |
| `Shown` | Client → Server | none (`ByteNet.nothing`) — "the prompt is on my screen; don't ask me again" |

## The dependencies

FavouritePrompt → GamemodeVote and PlayerData, both one-way, both hard requires
in the controller:

- **GamemodeVote** is the moment. Without it there's no beat to ask on, and
  nothing else in the game marks the end of a round.
- **PlayerData** is the memory. Without it "only once" is only once per session.

Nothing depends on FavouritePrompt. Remove the folder and the vote is unchanged.

## Constants worth knowing

`FavouritePrompt.Constants` (`src/features/FavouritePrompt/Constants.luau`):

| Key | Default | What it controls |
| --- | ------- | ---------------- |
| `PROMPT_DELAY` | `0` | Seconds between the ballot opening and the prompt. `0` puts it over the panels; `18` clears GamemodeVote's clock and result window. |
| `PROFILE_KEY` | `"FavouritePrompt"` | The profile slice holding `Prompted`. |

## Priority

`FavouritePromptService.Priority = 10` — after PlayerData (1) so `SetValue` is
ready. Nothing waits on it; the first write is a whole round away.

## Not built yet

- **The answer isn't recorded.** `PromptSetFavoriteCompleted` fires with an
  `Enum.AvatarPromptResult` and nothing listens. Wiring it to an Analytics step
  would turn "we asked 400 players" into a conversion rate — note the hard cap
  of ten funnels per experience (see [Analytics.md](Analytics.md)) before adding
  a funnel for it.
- **Whether they already favourited it isn't checked.** `GetFavorite` needs
  inventory read access, which is its own prompt — asking permission to ask is
  worse than occasionally asking someone who already said yes.
