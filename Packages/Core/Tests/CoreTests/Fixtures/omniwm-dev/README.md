# omniwmctl fixtures: OmniWM Dev

Captured from OmniWM Dev (Hans's fork `hans/main`, built from upstream `main`, protocol 22) on Hans's machine, 2026-11-05, with Dev's own `omniwmctl` (`~/Applications/OmniWM Dev.app/Contents/MacOS/omniwmctl`).

These check that the parsers written against the 0.7.6 fixtures (`../omniwm/`) still accept the newer protocol.

| File | How it was made |
|---|---|
| `subscribe-initial.ndjson` | `omniwmctl subscribe active-workspace,layout-changed,display-changed,focus,windows-changed --format ndjson`: ack + initial snapshot of the channels the bridge subscribes to |
| `query-workspaces.json` | `omniwmctl query workspaces --format json` |
| `query-displays.json` | `omniwmctl query displays --format json` |
| `query-windows-focused.json` | `omniwmctl query windows --focused --format json` |

At capture time: one display (Odyssey Ark, 3840 × 2160), outer gaps left/right 640, top 720, bottom 8, Safari and Claude tiled in Niri on workspace 1.
