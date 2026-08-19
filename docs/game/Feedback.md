# Feedback

One button, on the right of Roblox's topbar, that opens Roblox's own
in-experience feedback panel. The player writes what they think, and it arrives
in the Creator Dashboard.

The whole feature is an icon and a call. There is no packet, no profile slice, no
window and no server code — which is the reason to use Roblox's panel rather than
building a feedback window of our own: nothing here has to store, moderate or
ship anyone's text.

## The call

```lua
SocialService:PromptFeedbackSubmissionAsync({ FeedbackType = Enum.FeedbackType.Feedback })
```

| | |
| --- | --- |
| Realm | **Client only.** Both halves are: TopbarPlus reads `Players.LocalPlayer` at require time, and this is a client prompt. |
| Yields | For as long as the panel is up, so it's called on a spawned thread — the thread it would otherwise block is TopbarPlus's own event. |
| Throws | Rather than returning a result, when the panel can't be shown: an older client, a platform without it, the **Social capability** switched off for the place, or a second prompt asked for while one is already open. Wrapped in a `pcall` that warns; a button that can't open the panel does nothing visible rather than breaking the script that owns the topbar. |
| Takes | An options dictionary, **not a player** — the signature that reads like `(player, feedbackType)` is a different API. |

`Constants.TYPE` picks the flow. `Feedback` is "tell the creator what you think",
which is what a button labelled Feedback should open; `PlayerSupport` is the
support route, for a player who needs help rather than one who has an opinion, and
putting it behind this icon would send bug reports somewhere the creator never
reads them.

## The button

`FeedbackTopbar.client.luau`, registered as a UIRegistry **root** by
`FeedbackPresentation.client.luau` — the same shape as
[Settings](Settings.md)' and [DailyRewards](DailyRewards.md)' topbar buttons, with
one difference that's worth knowing:

**It has no selected state.** Those two open a UIShell frame this game draws, so
their icons stay lit while the window is up and are driven back down when it
closes. This one hands the screen to Roblox and gets it back, so the icon is
`oneClick(true)` and never stays lit. An icon left highlighted in front of a panel
the experience doesn't own would be claiming a toggle it doesn't have.

**It's on the right** (`Constants.ALIGNMENT`), beside Roblox's own controls,
because the panel it opens is one of theirs. The left-hand group is where this
game's own windows live. TopbarPlus sorts each alignment separately, so
`TOPBAR_ORDER` here is independent of the numbers Settings and Daily Rewards use.

Only a press with TopbarPlus's `"User"` source opens the prompt. The others are
the library's own bookkeeping — including the deselect that `oneClick` itself
causes — and a prompt fired off one of those would be a panel nobody asked for.

## Studio assets

None. The icon defaults to the shared `questionMark` from
`Shared.ui.assets.Icons`, so the feature installs with no Studio work; point
`Constants.ICON` at an `rbxassetid://` of your own for artwork that matches the
rest of the topbar.

## Constants

| Constant | Default | |
| -------- | ------- | - |
| `TYPE` | `Enum.FeedbackType.Feedback` | Which flow the panel opens. |
| `ICON` | shared `questionMark` | The topbar image. |
| `CAPTION` | `"Feedback"` | Label on hover, or on a long press on touch. |
| `ALIGNMENT` | `"right"` | Side of the topbar. |
| `TOPBAR_ORDER` | `1` | Order within that side. |
| `Presentations.topbar` | `true` | Off = the button goes, the feature is inert. |

## Verifying it

The call succeeds in a Studio play test (the icon appears in
`PlayerGui.TopbarStandard.Holders.Right` and the prompt returns without error),
but Roblox's panel is a CoreGui surface and is not reliably drawn in Studio.
Confirm the panel itself on a real client, in a published place.
