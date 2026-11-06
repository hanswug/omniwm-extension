# OmniWM Extension

A small native menu bar app that adds the commands and feedback [OmniWM](https://omniwm.app) is missing for Hans's workflow:

- **Padding presets.** Cycle or select `[gaps.outer]` presets (Fullscreen / Wide / Single, or your own).
- **Visible containers 1–5.** Writes `[niri] visibleContainerCount`, then tells OmniWM to Balance Sizes.
- **Borders toggle.** Flips `[borders] enabled`.
- **Live menu bar.** Shows the workspace, borders, a layout icon with container dots, and `F` / `FC`.
- **HUD** confirming every command, plus OmniWM's own fullscreen, layout and full-container toggles.
- **Display awareness.** On the built-in display alone, the first preset is applied; when you dock again, the previous padding comes back.

The spec is [`docs/PDR.md`](docs/PDR.md). Changes are listed in [`CHANGELOG.md`](CHANGELOG.md).

```
[icon] 1 - Code  |  ▢  |  ▥ ●●○○  |  FC
```

## Requirements

- macOS 26.0+ on Apple Silicon.
- OmniWM at `/Applications/OmniWM.app` with **IPC enabled** (`general.ipcEnabled = true`). Tested with OmniWM 0.7.6 (protocol 19) and OmniWM Dev built from upstream `main` (protocol 22).
- **Building only:** Xcode 27, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), `gh` for releases.

The app needs **no** Accessibility, Input Monitoring or other privacy permissions. Hotkeys use Carbon `RegisterEventHotKey`.

## Install

### From source (recommended)

```bash
scripts/create-signing-cert.sh   # once: creates the "OmniWM Extension Self-Signed" identity (asks for your password)
make install                     # build, sign, replace /Applications/OmniWM Extension.app, relaunch
```

Every build is signed with the same self-signed identity, so Start at login keeps working across updates. On the first build, choose **Always Allow** when `codesign` asks to use the key.

### From a GitHub release

```bash
gh release download v1.0.0 -R hanswug/omniwm-extension
unzip OmniWM-Extension-1.0.0.zip
shasum -a 256 -c OmniWM-Extension-1.0.0.zip.sha256
xattr -dr com.apple.quarantine "OmniWM Extension.app"
mv "OmniWM Extension.app" /Applications/
open "/Applications/OmniWM Extension.app"
```

The app is self-signed and not notarized, so removing the quarantine attribute is required.

## Update

- **From source:** `git pull && make install`.
- **From a release:** repeat the release steps above with the new version, after quitting the running app.

## Using it

- **Menu bar.** Left to right:
  - workspace `#` or `# - Name`;
  - borders `▢` (on) or a dashed square (off);
  - layout icon: three columns for Niri, a 2×2 grid for Dwindle;
  - visible containers (`●●○○`, or `5/5`; Niri only);
  - `F` when the focused window is fullscreen, `FC` when it fills the screen as a full container.

  When OmniWM isn't reachable, it shows `—` plus the borders segment.
- **Menu.** Warnings (config errors, hotkey conflicts, OmniWM not reachable), ⓘ override notices, Padding ▸, Visible containers ▸, Borders, Edit config file, Reload config, Start at login, Restart, Quit.
- **HUD.** Appears on the screen with the mouse, never takes focus, and never intercepts clicks.

## Configuration

`${XDG_CONFIG_HOME:-~/.config}/omniwm-extension/config.toml`. `XDG_CONFIG_HOME` is honoured only if it's an absolute path. The file is created with comments on first launch (or via **Edit config file**), and saved changes apply immediately. If the file is invalid, the last good config keeps running and the menu shows the error with its line number.

```toml
[general]
omniwm_settings = ""              # path to OmniWM settings; "" = the running OmniWM's (omniwm/ or omniwm-dev/settings.toml)
auto_fullscreen_on_builtin = true # built-in display alone → first preset; restore when docked again
balance_sizes_delay_ms = 120      # wait before Balance Sizes after a visible-containers change

[hud]
enabled = true
position = "center"               # center | top | bottom
duration_ms = 900

[hotkeys]                         # "" or omitted = unbound
cycle_padding        = "ctrl+opt+0"
toggle_borders       = "ctrl+opt+b"
visible_containers_1 = "hyper+1"
visible_containers_2 = "hyper+2"
visible_containers_3 = "hyper+3"
visible_containers_4 = "hyper+4"
visible_containers_5 = ""

[[padding]]                       # order = cycle order; the FIRST is used on the built-in display
name = "Fullscreen"
top = 8
bottom = 8
left = 8
right = 8
# hotkey = "ctrl+opt+1"           # optional: select this preset directly
```

| Key | Type | Default | Rules |
|---|---|---|---|
| `general.omniwm_settings` | string | `""` | empty (follow the running OmniWM), absolute, or `~/…` |
| `general.auto_fullscreen_on_builtin` | bool | `true` | |
| `general.balance_sizes_delay_ms` | number | `120` | clamped 0–2000 (warning) |
| `hud.enabled` | bool | `true` | |
| `hud.position` | string | `center` | `center` / `top` / `bottom` (case-insensitive) |
| `hud.duration_ms` | number | `900` | clamped 300–5000 (warning) |
| `hotkeys.*` | string | see above | one key plus at least one modifier |
| `padding` | array of tables | 3 presets | at least 1; `name` unique (case-insensitive) and non-empty; `top`/`bottom`/`left`/`right` numbers ≥ 0; optional `hotkey` |

**Hotkeys.**
- Format: case-insensitive, `+`-separated.
- Modifiers: `ctrl`, `opt` (or `alt`), `cmd`, `shift`, `hyper`. `hyper` means OmniWM's `general.hyperKeyModifiers`; it falls back to `ctrl+opt+shift+cmd` with a warning if that's missing.
- Keys: `a`–`z`, `0`–`9`, `f1`–`f20`, `space`, `tab`, `return`, `escape`, `left`, `right`, `up`, `down`, `minus`, `equal`, `comma`, `period`, `slash`, `semicolon`, `quote`, `backslash`, `leftbracket`, `rightbracket`, `grave`.
- The same chord bound twice is an error.
- A chord also bound in OmniWM is still registered, with a warning.
- Unknown keys are warnings, not errors.

## How it touches OmniWM

- **Writes go to `settings.toml` only**, because OmniWM's IPC can't set gaps, borders or the container count.
  - Each edit changes just the value on the target line; every other byte stays identical.
  - Writes are atomic (temp file + rename), keep the file's permissions, and follow a symlinked `settings.toml`.
  - If OmniWM changes the file at the same moment, the app re-reads and re-applies once, then reports an error rather than overwriting OmniWM's change.
  - A change to a value that's already set doesn't write.
- **Per-monitor overrides.** The app writes only global values. If `monitorGapOverrides` or `monitorNiriOverrides` masks a change on the current display, the HUD says so and the menu shows ⓘ.
- **Release or Dev.** The app talks to whichever OmniWM is running. While OmniWM Dev (`make run` in an OmniWM checkout) runs, it uses Dev's own `omniwmctl` and `~/.config/omniwm-dev/settings.toml`, and switches back when Dev quits. An explicit `omniwm_settings` path always wins.
- **State from IPC.** A long-lived `omniwmctl subscribe` child process provides live state. It restarts with backoff 1 → 2 → 5 → 10 s and is killed when the app quits.
- **Inferred toggles.** OmniWM's IPC has no command events, so its toggles are recognised from state changes. Leaving fullscreen emits no event at all, so the focused window is also polled: every 0.5 s while `F`/`FC` is shown, otherwise every 1.5 s, each poll taking a few milliseconds.
- **Display state** is kept in `~/Library/Application Support/com.omniwm.extension/state.json` (`lastTopology`, `lastExternalGaps`).

## Troubleshooting

Live logs (categories `app`, `config`, `settings`, `hotkeys`, `bridge`, `display`):

```bash
log stream --predicate 'subsystem == "com.omniwm.extension"'
```

Add `--level debug` to also see every menu bar update and each settled OmniWM state.

| Symptom | Fix |
|---|---|
| Menu bar shows `—`, menu says "OmniWM not reachable" | Is OmniWM running? Is `general.ipcEnabled = true`? `/Applications/OmniWM.app/Contents/MacOS/omniwmctl ping` should print `pong`. The app reconnects by itself. |
| `⚠ Couldn't register ctrl+opt+…` | Another app owns that chord. Pick another in `config.toml`. |
| `⚠ … also bound in OmniWM (…)` | Both apps react to the chord. Change one of them. |
| `make build`: identity not found | Run `scripts/create-signing-cert.sh` once. |
| "App is damaged / can't be opened" after downloading | `xattr -dr com.apple.quarantine "/Applications/OmniWM Extension.app"` |
| Columns don't re-lay out after `hyper+N` | Raise `general.balance_sizes_delay_ms` (OmniWM may need longer to reload on a busy or slower Mac). |
| Start at login doesn't stick | macOS may need approval: System Settings → General → Login Items. |
| `Couldn't write OmniWM settings` | See the `settings` log. Typical causes: OmniWM rewrote the file at the same moment twice, or a table (`[gaps.outer]`, `[niri]`, `[borders]`) is missing. The app never creates tables. |
| Padding unexpectedly switched after (un)docking | That's `auto_fullscreen_on_builtin`; set it to `false` to keep padding unchanged. |

## Development

```bash
make gen        # regenerate the Xcode project (after editing project.yml)
make test       # Core unit tests (Swift Testing)
make build      # signed release build into build/
make run        # build and launch
make install    # replace /Applications/OmniWM Extension.app and relaunch
make release VERSION=x.y.z   # see docs/PDR.md §7.3
```

- All logic lives in `Packages/Core` (no AppKit). The app target in `App/` is a thin AppKit/SwiftUI shell.
- Only dependency: TOMLKit, pinned at exactly 0.6.0.
- Parsers are written against captured fixtures in `Packages/Core/Tests/CoreTests/Fixtures/`: a copy of the real `settings.toml` and `omniwmctl` output (see its README). Re-capture them after OmniWM updates.

## License note

Private, personal build. The app and menu bar icons are derived from OmniWM's icon (OmniWM is GPL-2.0). Revisit before publishing this repository.
