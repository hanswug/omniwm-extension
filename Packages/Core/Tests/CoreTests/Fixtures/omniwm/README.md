# omniwmctl fixtures

Captured from OmniWM 0.7.6 (protocol 19) on Hans's machine, 2026-11-05 (PDR §6.7).
Parsers are written against these files, not the docs.

| File | How it was made |
|---|---|
| `subscribe-initial.ndjson` | `omniwmctl subscribe --all --format ndjson` — ack + initial snapshot of every channel |
| `toggle-fullscreen.ndjson` | `subscribe --all --no-send-initial` while running `command toggle-fullscreen` twice (on, off). **Off emits no event.** The on event carries the pre-layout frame. |
| `toggle-workspace-layout.ndjson` | same, `command toggle-workspace-layout` twice (niri → dwindle → niri) |
| `toggle-full-span.ndjson` | same, `command toggle-container-full-primary-span` twice. Only `layout-changed`; the other column's `viewport` goes `after` and back. No `windows-changed`. |
| `switch-workspace.ndjson` | same, `command switch-workspace 2` then `1` |
| `query-*.json` | `omniwmctl query … --format json` (`windows --focused` also while fullscreen / full span) |
| `transport-failure.ndjson` | `OMNIWM_SOCKET=/nonexistent.sock omniwmctl subscribe … --reconnect` — exits 2 immediately |
| `edge-cases.ndjson` | hand-made: truncated JSON, garbage, unknown channel, unknown kind, blank line, between real lines |

Mid-stream disconnects are reported on **stderr**: `omniwmctl: connection lost: …`, `omniwmctl: reconnect failed: …`, `omniwmctl: reconnected`.
