# Switchboard Tool (SBT)

A small resident macOS app that replaces the parts of BetterTouchTool I actually use: it routes trackpad taps, key
combinations and screen corners to actions. The name nods to BTT on purpose. Target: macOS 26 (Tahoe). Written in Swift.
The project folder is still called `BTT_Alternative`.

## Decisions (2026-10-10)

- Two apps. The **Agent** (menu-bar resident; holds the Accessibility permission, intercepts input and performs actions)
  and the **launcher** (Launchpad replacement) are kept separate. The launcher is LaunchNext; its source and build live
  next door in `../LaunchNext/` (see `../LaunchNext/README.md`). Verdict: good. Opening and closing from the screen corner
  uses LaunchNext's own hot-corner setting ("Close when already open").
- The secondary click stays on "click in bottom-right corner", so the two-finger-tap right click has to be custom
  (macOS allows only one secondary-click method).
- The Agent handles: two-finger tap → right click, key bindings → Return / click / desktop switching, and, if wanted,
  hot corners → open an app.
- Ad-hoc signing; no self-signed certificate. After a rebuild the Accessibility permission has to be granted again.
  Note: the permission record binds to the code hash the app had when it first asked. After a rebuild, switching the
  toggle on does nothing (tccd logs "Failed to match existing code requirement"). `make_app.sh` therefore runs
  `tccutil reset Accessibility <bundle id>` after building, so the next launch creates a fresh record.
- All work stays inside this folder.

## Layout

- `Package.swift` — one package, three targets.
  - `Sources/CMultitouch` — entry point to Apple's private MultitouchSupport framework (C), loaded with dlopen at runtime.
  - `Sources/TouchProbe` — test tool: `touch` (log finger data), `click` (right click after 3 s), `tap2click` (two-finger tap → right click).
  - `Sources/SwitchboardTool` — the Agent, including the settings window (SwiftUI).
- `make_app.sh` — builds both and assembles `build/TouchProbe.app` and `build/SwitchboardTool.app`.
- `config.example.json` — a config that shows every feature.

## Using the Agent

- A hand icon appears in the menu bar; a warning triangle while the permission is missing.
- The first launch asks for Accessibility. Once granted, the icon changes within 2 seconds.
- **Settings…** in the menu opens a window that edits everything below: trackpad gestures, hot corners,
  key bindings (type the combination or press Record and hit the keys) and tuning. Changes are saved to
  the config file and applied right away. Key bindings pause while the window is open.
- Config: `~/Library/Application Support/Switchboard Tool/config.json` (written with defaults on first launch).
  It can also be edited by hand; "Reload Config" in the menu applies it. Unreadable parts are listed in the menu with a count.
- Logs: `/usr/bin/log stream --predicate 'subsystem == "io.github.masaakiu.switchboardtool"' --level info`

### Config format

```json
{
  "gestures":    { "two_finger_tap": "right_click", "three_finger_swipe_left": "space_left",
                   "two_finger_swipe_down_from_top": "mission_control" },
  "hot_corners": { "bottom_right": { "open_app": "LaunchNext", "dwell_ms": 200 } },
  "keys":        { "ctrl+alt+return": "return", "ctrl+alt+right": "space_right" },
  "tuning":      { "tap_max_ms": 200, "tap_max_move": 0.03, "swipe_min_distance": 0.2, "swipe_max_ms": 600,
                   "edge_band": 0.08, "corner_dwell_ms": 200, "corner_tolerance_px": 2 }
}
```

Gestures: `<fingers>_finger_tap`, `<fingers>_finger_swipe_<direction>` and
`<fingers>_finger_swipe_<direction>_from_<edge>` with fingers `two`…`five`, directions `left right up down`,
edges `top bottom left right` (an edge swipe starts inside the band along that edge and moves away from it;
without its own binding it counts as the plain swipe). Plain two-finger swipes are scrolling and are not offered.
Swipes with three or more fingers are also seen by macOS: turn the matching system gesture off in
System Settings › Trackpad, or both will fire.

| Action | Meaning |
|---|---|
| `right_click` / `left_click` / `middle_click` | click at the cursor position |
| `return`, `escape`, `ctrl+right`, any key combination | send that key |
| `space_left` / `space_right` | switch desktop (sends Ctrl+←/→) |
| `mission_control` / `app_expose` / `apps` / `show_desktop` | Mission Control / App Exposé / Tahoe's Apps view / Show Desktop |
| `lock_screen` / `screenshot_area` | Ctrl+Cmd+Q / Cmd+Shift+4 |
| `volume_up` / `volume_down` / `mute` / `play_pause` / `next_track` / `previous_track` / `brightness_up` / `brightness_down` | media keys |
| `{ "open_app": "name, bundle id or path" }` | open an app |
| `{ "key": "cmd+shift+4" }` | send a key combination |

Corners: `top_left`, `top_right`, `bottom_left`, `bottom_right`.
Key names: see `Sources/SwitchboardTool/KeyCodes.swift` (`a`–`z`, `f1`–`f20`, `left`, `eisu`, `kana`, …).
Modifiers: `cmd`, `ctrl`, `alt`, `shift`, `fn`. `fn` is only compared when the trigger mentions it.

## Test log

- 2026-10-10 TouchProbe `touch`: finger frames arrive from MultitouchSupport with Input Monitoring denied and no Accessibility permission.
- 2026-10-10 TouchProbe `touch`, 15 s operated by the user: about 40 two-finger taps, all detected, no misses, no false positives.
  Tap length 32–80 ms, movement 0.002–0.013 (limits 0.30 s / 0.03). One-finger moves (0.3–0.45 s, movement 0.1) correctly excluded.
- 2026-10-10 TouchProbe `tap2click`: `AXIsProcessTrusted` stayed false after the user granted the permission.
  Cause: the 18:50 build had already created the permission record when it called `AXIsProcessTrusted()`; the 18:55 rebuild
  no longer matched it (tccd: "Failed to match existing code requirement"). Fix: `tccutil reset`, now part of `make_app.sh`.
- 2026-10-10 Agent (then called BTT Alternative): the user confirmed the two-finger tap opens the right-click menu right after granting Accessibility.
  LaunchNext opens and closes from the bottom-right corner through its own setting. Key bindings not yet exercised at that point.
- 2026-10-10 Renamed to Switchboard Tool; bundle id io.github.masaakiu.switchboardtool.
- 2026-10-15 Key bindings were dead although the settings window was closed; `CGGetEventTapList` showed the tap registered but
  disabled. Cause: the closing report comes from windowWillClose, while the window still reports visible, so the tap was never
  restarted; stop() also left the port registered. Both fixed; the tap's starts, stops and firings now log at notice level.

## License

MIT. See [LICENSE](LICENSE).
- 2026-10-11 Added swipes and edge swipes to the gesture engine, media-key and system actions, and the settings window.
