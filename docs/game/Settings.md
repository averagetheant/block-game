# Settings

Player settings with a feature-extensible registry. Settings persist to the player's profile via the existing PlayerData feature (ProfileStore + Replica), so reads are zero-latency on the client and writes survive across sessions.

The Settings feature itself ships **no real settings** — it provides the registry, persistence, networking, and UI. Other features declare their own categories and toggles.

## What it does

- **Registry** (`Registry.luau`, shared): two flat tables (`settings`, `categories`) with a `Changed` signal. Both client and server load this module; both realms keep their own copy.
- **Persistence**: setting values live under a `Settings = {}` key on the player profile as a `[settingId] = value` map. That key is registered into the PlayerData profile template by `src/features/Settings/PlayerData.luau` (see docs/game/PlayerData.md) — the PlayerData feature itself doesn't know Settings exists. Writes route through `PlayerDataService.SetValue` so the Replica diff and the next ProfileStore autosave stay in sync.
- **Networking**: one ByteNet packet per setting kind. Today there's just `SetToggle`; new kinds add their own packet.
- **UI**: `SettingsUI.ui.luau` is a pure React component (sections, values, onToggle, focusedId as props). `SettingsView.client.luau` wires it to `PlayerDataController`, `Registry.Changed`, and `SettingsController.LinkRequested`.
- **Linking**: `SettingsController.linkTo("audio.music")` fires a signal the UI listens to and briefly highlights that row.

## Presentations

Settings is reachable from four surfaces, gated individually by
`Constants.Presentations`. They're peers — none references another, and they
stay in sync by routing through the same core intent
(`SettingsController.setToggle`) and the same UIShell frame state.

| Flag | File | Surface |
| ---- | ---- | ------- |
| `screen` | `SettingsPresentation.client.luau` | The window contents, registered as a UIShell *screen*. |
| `topbar` | `SettingsTopbar.client.luau`, registered by the same presentation | A TopbarPlus icon in Roblox's native topbar that toggles that frame. Registered as a *root*. |
| `sidebar` | `Sidebar.luau` | The left-rail icon that opens the same frame. |
| `world` | `SettingsWorldInteraction.client.luau` | Parts tagged `SettingsToggleStation` that flip one setting via a ProximityPrompt. |

`sidebar` and `topbar` are deliberately redundant — both open the same window.
Ship one, or both; turning either off leaves Settings reachable through the
rest.

### The topbar icon

`SettingsTopbar.client.luau` is the same shape as `DailyRewardsTopbar` — see
that file if you're adding a third. It renders **no instance**: TopbarPlus
(`ReplicatedStorage.Packages.TopbarPlus`, Wally `1foreverhd/topbarplus`) owns
its own ScreenGui outside the React tree, so the component returns `nil` and
ties the `Icon`'s lifetime and selected state to React through effects. It goes
in as a *root* rather than a screen because a root is always mounted (a screen
only renders inside an open window) and sits inside `FrameProvider`, so it can
call `useFrame()`.

State syncs both ways: clicking the icon opens the frame, and opening the frame
from the rail (or via `Settings.linkTo`) lights the icon up. The `deselected`
handler only closes when Settings is the frame that's actually open — TopbarPlus
deselects an icon whenever another one is selected, and without that guard the
button would slam shut a window it didn't open.

Two things the shared UI rules don't cover here:

- **No skin, no theme, no 1280×720 reference.** TopbarPlus sizes itself against
  the real topbar and handles mobile and gamepad on its own. Restyle through
  `Icon.modifyBaseTheme` / `:modifyTheme`, not `src/shared/ui/`.
- **No UI Labs story**, same as `DailyRewardsTopbar`. A story would need a
  `<FrameProvider>` to render at all (`useFrame()` errors without one), and
  mounting it would spawn a real topbar icon in the Studio session rather than
  draw anything in the preview pane.

Client realm (`.client.luau`, not `.ui.luau`) on purpose: TopbarPlus reads
`Players.LocalPlayer` and builds its container at require time, so the server
must never load it.

## Studio assets it expects

None. Everything is code — the topbar icon uses `assets.Icons.settings`, the
same placeholder image as the rail entry. Swap it for your own art.

## Packets it speaks

| Packet      | Direction       | Payload                            | Notes |
| ----------- | --------------- | ---------------------------------- | ----- |
| `SetToggle` | client → server | `{ id: string, value: boolean }`   | Server validates id against the Registry, type-checks `kind == "toggle"`, then writes via `PlayerDataService.SetValue({ "Settings", id }, value)`. |

## Adding settings from another feature

Two patterns. Pick the one that fits how your feature is structured.

### 1. Auto-discovery (preferred for static settings)

Drop a `Settings.luau` file as a sibling of your feature's `init.luau`:

```lua
-- src/features/MyFeature/Settings.luau
return function(Settings)
    Settings.registerCategory({
        id = "myfeature",
        title = "My Feature",
        order = 50,
    })

    Settings.registerSetting({
        kind = "toggle",
        id = "myfeature.cool_thing",
        label = "Enable Cool Thing",
        category = "myfeature",
        default = true,
        order = 1,
        variant = "blue", -- optional checkbox palette
    })
end
```

The Settings feature's `init.luau` walks `ReplicatedStorage.Features:GetChildren()` at load time, finds any `Settings` ModuleScript child, requires it, and calls the returned function with the `Settings` table. This runs on **both** realms — `SettingsService` and `SettingsController` each `require(Features.Settings)` for the side effect (just requiring submodules like `Settings.Constants` is not enough; it doesn't run `init.luau`).

The discovery file is required exactly once per realm, so put only registration calls inside — no service start-up logic, no `Players.PlayerAdded` connections.

### 2. Manual registration (for dynamic / runtime settings)

Require the Settings feature from anywhere shared code runs and call the register API directly:

```lua
local Settings = require(ReplicatedStorage.Features.Settings)

Settings.registerCategory({ id = "myfeature", title = "My Feature" })
Settings.registerSetting({ kind = "toggle", id = "myfeature.cool_thing", ... })
```

If you call this *after* the Settings UI has mounted, the `Registry.Changed` signal will trigger a re-render so the new entry appears live. Use this when registrations depend on runtime state (e.g. unlocked content).

## Reading values from feature code

```lua
local SettingsController = require(StarterPlayerScripts.Features.Settings.SettingsController)

local enabled = SettingsController.get("myfeature.cool_thing")
-- Returns the persisted value, or the registered default if the player hasn't
-- toggled it yet. Returns nil only if the id isn't registered.
```

For React components, subscribe via `useReplica` directly so the component re-renders when the value changes:

```lua
local utils = require(ReplicatedStorage.Shared.utils)
local Settings = require(ReplicatedStorage.Features.Settings)

local function MyComponent()
    local values = utils.useReplica(PlayerDataController, Settings.Constants.PROFILE_KEY) or {}
    local enabled = values["myfeature.cool_thing"]
    if enabled == nil then
        enabled = Settings.Registry.getSetting("myfeature.cool_thing").default
    end
    -- ...
end
```

## Writing values from feature code (client)

```lua
local SettingsController = require(StarterPlayerScripts.Features.Settings.SettingsController)
SettingsController.setToggle("myfeature.cool_thing", false)
```

The client never mutates the value locally — the ByteNet packet round-trips through the server, which validates against the Registry and routes the write through `PlayerDataService.SetValue`. The Replica diff comes back and the UI updates from `useReplica`.

## Linking from another UI

```lua
local UIShell = require(ReplicatedStorage.Features.UIShell)
local Settings = require(ReplicatedStorage.Features.Settings)
local SettingsController = require(StarterPlayerScripts.Features.Settings.SettingsController)

-- Inside a React component:
local frames = UIShell.useFrame()
local function onClick()
    frames.open(Settings.FRAME_ID)
    SettingsController.linkTo("audio.music")
end
```

The Settings UI listens to `LinkRequested`, sets the row's `focusedId` for `Constants.LINK_HIGHLIGHT_SECONDS`, and renders that row with a brighter Panel transparency so it visibly pulses out of the list.

## Constants worth knowing

- `Constants.PROFILE_KEY = "Settings"` — the key under `PlayerData` where values live. Don't write directly; use `SettingsController.setToggle` (client) or let `SettingsService` route packets (server).
- `Constants.MAX_SETTING_ID_LENGTH = 128` — defensive cap on inbound packet ids.
- `Constants.LINK_HIGHLIGHT_SECONDS = 1.6` — how long the link highlight lingers.
- `Settings.FRAME_ID = "Settings"` — UIShell frame id used by the HUD's Settings sidebar entry, and by the topbar icon.
- `Constants.TOPBAR_ORDER = 2` — sort key among topbar icons, low → high. DailyRewards claims 1.
- `Constants.TOPBAR_CAPTION = "Settings"` — hover / controller caption. `""` for none.

## Extending with new setting kinds

To add (say) a slider:

1. Add a `SliderSetting` shape to `Registry.luau`'s `Setting` union and extend the type with `min`, `max`, `step`, `default: number`.
2. Add a `SetSlider` packet to `Packets.luau`.
3. Add a `SetSlider.listen(...)` handler in `SettingsService` mirroring `SetToggle` (validate `def.kind == "slider"`, clamp `payload.value` to `[def.min, def.max]`, route to `PlayerDataService.SetValue`).
4. Add `SettingsController.setSlider(id, value)`.
5. Extend the `for _, def in section.settings` loop in `SettingsUI.ui.luau` with a `def.kind == "slider"` branch that renders a slider primitive.

The kind union threads through registry → packet → service validation → UI rendering. Keep the chain in lock-step.
