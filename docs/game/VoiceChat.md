# VoiceChat

Server-wide voice — every player hears every other player, at full volume,
anywhere on the map — plus a column of chips in the bottom-left corner naming
whoever is talking right now.

## The two settings this depends on

Voice is configured on the `VoiceChatService` **place settings**, which live in
the place file rather than in code. A script can read them but can't usefully
change them, so both are set once in Studio (Explorer → VoiceChatService):

| Property | Value | Why |
| -------- | ----- | --- |
| `UseAudioApi` | `Enabled` | Puts an `AudioDeviceInput` behind every player's microphone. Without it there is nothing to wire, and nobody hears anybody. |
| `EnableDefaultVoice` | **`false`** | Turns off Roblox's proximity voice graph. Left on, that graph runs *alongside* this one and anyone standing near you is heard twice. |

Voice also has to be enabled for the experience itself on the Creator Dashboard,
and an individual player only has a working microphone if they're age-verified
and have voice switched on for their account. Neither is something the game can
set.

`VoiceService` reads both properties at startup and warns with the exact fix if
either is wrong, so a place that drifts says so in the output rather than going
quietly silent.

## The audio graph

Roblox's default voice is positional: your microphone feeds an `AudioEmitter` on
your character, and every listener mixes that emitter against an `AudioListener`
on their camera, so how well someone hears you depends on how close they are.

This feature replaces that with a flat graph, built fresh on each client:

```
              server                     |            each client
                                         |
  Players.Ana.AudioDeviceInput  ---------+--> Wire --> AudioAnalyzer   (level)
                                         |    \
                                         |     `--> Wire --> AudioDeviceOutput
  Players.Ben.AudioDeviceInput  ---------+--> Wire --> AudioAnalyzer
                                         |    \
                                         |     `--> Wire --> AudioDeviceOutput
  Players.You.AudioDeviceInput  ---------+--> Wire --> AudioAnalyzer
                                         |         (no output wire — that would
                                         |          play your own voice back)
```

No emitters, no listener, no positions anywhere in it. A `Wire` can't attenuate,
so distance stops mattering — that's the whole of "universal".

**Who owns what.** The server owns *whose microphone exists* (`AudioDeviceInput`
has to be server-created to be trusted with a `Player`) and nothing else. Every
client builds its own mix out of local instances, so no client can change what
anyone else hears. The graph lives in `SoundService.VoiceChatGraph`, one folder
per player, which makes cleanup a single `Destroy`.

The inputs keep their default access (deny-list, empty — nobody excluded). That
is what "everybody hears everybody" means; narrow *that* if the game ever needs
private voice, never the wiring.

**Exactly one input per player, and it has to be the live one.** With default
voice on, the engine creates its own `AudioDeviceInput` as the voice session
connects — after the player has joined. A second input made alongside it isn't a
duplicate microphone, it's a dead one: only the engine's carries the stream, and
a meter on the other reads silence however loudly anyone talks. That failure is
invisible — voice works, the indicator simply never appears — so it's guarded
from both ends. `VoiceService` creates an input only when default voice is off
(and destroys its own if an engine one turns up anyway); `VoiceController` picks
the input whose `Active` is true and re-points the graph if that changes.

## Who's talking

There is no "is this player speaking" API. Instead each microphone is also wired
to an `AudioAnalyzer`, and `RmsLevel` — the actual loudness of the stream the
client is already receiving — answers the question directly, identically for
everyone including yourself.

`VoiceController` samples every analyzer at `POLL_INTERVAL` (15 Hz):

- above `SPEAKING_RMS`, the player counts as talking,
- and keeps counting for `HOLD_SECONDS` after they drop below it. Speech is full
  of gaps between words; without the hold a chip flickers several times a
  sentence.

The list is ordered by when each run of talking began, so the column doesn't
reshuffle every time someone pauses for breath.

`Changed` fires only when the *set* of speakers changes. Levels are read through
`levelOf(userId)` instead, which is what lets a chip animate its ring every frame
without re-rendering the corner of the HUD sixty times a second.

## The chips

`SpeakerList` draws one chip per speaker — headshot, display name, and a ring
around the headshot that swells with their microphone. It's anchored by its
bottom-left corner and sized to its contents, so the column grows *upward* out
of the corner as more people talk.

There's no panel behind a chip and no box around one. The widget is ambient — it
appears while somebody talks and is gone a moment later — and a surface per
speaker would stack boxes in the corner for something nobody interacts with. The
avatar ring and the label's own text outline carry it against the world instead,
which is also why the ring is the one stroke in the whole thing.

`EDGE_MARGIN` / `BOTTOM_OFFSET` put the column right down in the corner, in the
dead space below the sidebar rail. It's low enough to share that corner with the
controls hint for the hint's first few seconds; the hint fades on its own and the
chips only exist while someone is talking, so the overlap is brief either way.
Raise `BOTTOM_OFFSET` (to about 160) to clear the hint completely.

Past `MAX_SHOWN` (4) the column stops growing and reports the rest as a count.
Trimming takes the *oldest* talkers off, so somebody who just started speaking is
always on screen — the alternative, in a full server, is four people who happened
to speak first and never seeing whoever is talking now.

Iterate the visuals in the UI Labs story (`SpeakerList.story.luau`): `level`
drives every ring at once, and `speaking` past 4 shows the overflow row.

## Files

| File | Realm | Role |
| ---- | ----- | ---- |
| `Constants.luau` | shared | Routing names, speaking thresholds, chip sizes, `Presentations`. |
| `VoiceService.server.luau` | server | Exactly one `AudioDeviceInput` per player; warns on a misconfigured place. |
| `VoiceController.client.luau` | client | Builds this listener's graph; decides who's talking. Headless. |
| `SpeakerList.ui.luau` | shared | The chips. Dumb — everything arrives as props. |
| `SpeakerList.story.luau` | shared | UI Labs story. |
| `VoiceView.client.luau` | client | Wires the controller's state into the chips. |
| `VoicePresentation.client.luau` | client | Registers the column as an always-mounted root. |

`Presentations.screen = false` drops the chips and leaves the voice routing
untouched — the routing is controller work, not a presentation.

## Studio assets

None. Nothing here needs a part, a tag, or an uploaded asset — only the two
`VoiceChatService` properties above.
