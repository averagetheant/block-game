# ChatHints

A tip line in the general chat channel every five minutes:

> **Tip** The stronger the supports of the tower are, the more likely it'll stand!

**The feature ships no tips.** It owns the mechanism — the clock, the channel and
a rotation that doesn't repeat — and knows nothing about towers, streaks or
reactions. Every hint is declared by the feature it's about, in a sibling
`ChatHints.luau` that ChatHints' auto-discovery loop picks up on both realms —
the same convention PlayerData / Settings / Store / Sidebar / DailyRewards use.

## Files

| File | Realm | What it is |
| ---- | ----- | ---------- |
| `init.luau` | shared | The public surface (`registerHint`, `registerHints`, `list`) and the auto-discovery pass. |
| `Registry.luau` | shared | The hint table, the `Hint` type, sorted `list()`. |
| `Constants.luau` | shared | Cadence, channel, colours, the `Presentations` gate. |
| `ChatHintsController.client.luau` | client | The loop that draws a hint and prints it. |

## Studio assets

None — but the place must be on **TextChatService** (the default since 2023). On
a place still running the legacy chat, `TextChannels` never appears, the
controller gives up after `CHANNEL_WAIT_SECONDS` and the game runs without tips.
No error: the game is playable without them.

## Adding a hint

Drop a `ChatHints.luau` in your feature folder. It returns
`function(ChatHints) … end` and never requires `Features.ChatHints` itself (that
would be circular) — the table arrives as the argument:

```lua
-- src/features/Pets/ChatHints.luau
return function(ChatHints)
	ChatHints.registerHints({
		{ id = "pets.equip", order = 1, text = "Equip a pet from the Pets window and it follows you between rounds." },
		{ id = "pets.hatch", order = 2, text = "Eggs hatch faster the more you place." },
	})
end
```

| Field | | |
| ----- | - | - |
| `id` | required | Unique across **every** feature's hints. Also the "don't repeat the last line" key, so namespace it (`pets.equip`). A duplicate warns and overwrites. |
| `text` | required | One line, one idea. Read in a glance in a chat window or not at all. |
| `order` | optional | Sorts the seed list (low → high). Only a grouping convenience — the rotation is shuffled, so this is not a schedule. |

`registerHint(def)` takes one; `registerHints({…})` takes a list.

**Quote tunables, don't retype them.** The registration file is a normal module —
`require(script.Parent.Constants)` and interpolate, so a tip can't outlive the
number it quotes:

```lua
text = `An untouched turn is only {Constants.IDLE_TURN_SECONDS} seconds long.`,
```

**Hint text is rich text.** `<b>`, `<font color="…">` and friends work, because
every hint is written by whoever ships the feature. If you ever build one out of
a runtime string (a player's name, a server value), escape it first — see
`TowerAnnounceController` for that pattern.

The registry is **not sealed** after discovery: the controller re-reads it each
time it refills, so a late registration joins the next rotation.

## Why the client owns the clock

A system message is local to the player who sees it, and a tip is advice for one
player rather than an event the room shares — so there is nothing for the server
to say and no packet to send. Each client runs its own clock from the moment it
joined, which means two players who joined a minute apart read their hints a
minute apart. That's the intent: the rotation is paced to a *session*, not to
server uptime, so a player who joins during a storm still gets their first hint a
minute later instead of whenever the server's cycle happens to come round.

## The rotation is a shuffle bag

Every hint is shown once before any is shown twice, and a fresh bag never opens
with the hint the last one closed on. Plain random repeats often enough at this
cadence that a player reads the same line twice inside six minutes — and a line
they've already read twice is a line they stop reading.

## Constants worth knowing

| Constant | Default | |
| -------- | ------- | - |
| `INTERVAL_SECONDS` | `300` | Seconds between hints. One per storm stage — TowerGame's `STORM_SECONDS` is also 300. |
| `FIRST_HINT_SECONDS` | `60` | Delay before the first one, so it doesn't land while the place is still streaming in. |
| `CHANNEL` | `"RBXGeneral"` | The channel to print into — the one everyone already has open. |
| `CHANNEL_WAIT_SECONDS` | `15` | How long to wait for chat to exist before giving up. |
| `PREFIX` / `PREFIX_COLOR` | `"Tip"` / `#7dd3ff` | The coloured label, so a hint reads as a hint without being read. |
| `TEXT_COLOR` | `#dfe7ef` | The body, a shade under chat white. |
| `Presentations.chat` | `true` | Off = the hints stop, every registration stays put. |

## Who registers what today

| Feature | Hints |
| ------- | ----- |
| TowerGame | 13 — supports and foundations, the storm clock and checkpoints, the turn clock and the idle rules, special pieces, the vote and PVP. |
| Store | 2 — where coins are spent, where things are equipped. |
| DailyRewards | 2 — claiming, and how the run breaks. |
| Reactions | 2 — sending one, swapping the bar. |
