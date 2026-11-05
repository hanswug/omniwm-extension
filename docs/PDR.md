# OmniWM Extension — Product Design & Requirements (PDR)

| | |
|---|---|
| App name | OmniWM Extension |
| Bundle ID | `com.omniwm.extension` |
| Repo | `github.com/hanswug/omniwm-extension` (private) |
| Owner | Hans (`hanswug`) — sole user, sole approver |
| Target | macOS 27.0.1+, Apple Silicon, Swift 6 |
| Versioning | SemVer, `0.x` per task, `1.0.0` when all tasks ship |
| Distribution | Self-signed, GitHub Releases, manual updates |

---

## 1. Purpose

OmniWM is a tiling window manager for macOS. It lacks a few commands Hans uses daily and gives no at-a-glance feedback on them. Today these live as Raycast bash scripts that edit `~/.config/omniwm/settings.toml`. This app replaces them with a native menu bar app that:

1. Executes the missing commands via global hotkeys and menu items.
2. Shows the relevant OmniWM state live in the menu bar.
3. Confirms every command with a short HUD.

### Non-goals
- No settings GUI. Configuration is a TOML file only.
- No auto-updater (private repo; manual updates).
- No App Store / notarization (no Apple Developer account).
- No per-monitor presets in v1 (only global gaps; see §6.6).
- The app does not manage the existing Raycast scripts.

---

## 2. Facts about OmniWM this design depends on

Verified against omniwm.app docs (Nov 2026). Re-verify anything marked ⚠ against the installed version during the relevant task.

| Fact | Consequence |
|---|---|
| Config: `${XDG_CONFIG_HOME:-$HOME/.config}/omniwm/settings.toml` (XDG only if absolute). Live-reloaded on save. | The app changes settings by editing this file. |
| **IPC has no command to set borders, gaps, or visible container count.** | All three are file edits. IPC is read-only for us. |
| `omniwmctl` is bundled at `/Applications/OmniWM.app/Contents/MacOS/omniwmctl`. | Always call the bundled binary (fallback: `PATH`). Never implement the wire protocol. |
| Wire protocol version must match **exactly** and changes between releases (docs show 21 and 22). | Reason for using `omniwmctl` and not a native socket client. |
| IPC socket `~/Library/Application Support/com.barut.OmniWM/ipc.sock`, token in `ipc.sock.secret`. Requires `general.ipcEnabled = true`. | `omniwmctl` handles both. App shows "not reachable" when IPC is off. |
| `omniwmctl subscribe <channels> --reconnect --format ndjson` streams events. Channels used: `active-workspace`, `layout-changed`, `display-changed`. Initial snapshots are sent unless `--no-send-initial`. | One long-lived child process feeds live state. |
| `omniwmctl query workspaces` returns `layout`, `number`, `display-name`, `is-current`, `columns` (Niri only). ⚠ JSON key casing not documented. | Capture real output into test fixtures in task 0.6.0. |
| `display-changed` fires on display add/remove/reconfigure **and on gap-setting change**. `displays` includes resolved `outer-gap-*` per display. | Used to detect per-monitor gap overrides. |
| No IPC field for borders. | Borders state comes from `settings.toml`. |
| OmniWM itself writes `settings.toml` (monitor setup, overview zoom, upgrades). | Edits must be surgical and atomic (§6.1). |
| `[[workspaces]]`: `name` is the number (ordering/keys), `displayName` is an optional label. | Workspace label format (§5.1). |
| `general.hyperKeyModifiers` defines Hyper (currently `"Control+Option+Shift+Command"`). | `hyper` in our config resolves to this value. |
| `[[hotkeys]]` entries: `binding = "Control+Option+H"` or `"Unassigned"`. | Used for conflict detection. |
| `[[monitorGapOverrides]]` and `[[monitorNiriOverrides]]` (can override `visibleContainerCount`) exist per display. | The app writes globals only and warns when an override masks the change (§6.6). |
| `niri.visibleContainerCount`: integer, app max 6. | Commands 1–6. |
| A file change to `visibleContainerCount` is reloaded but existing columns only re-lay out after **Balance Sizes** (`omniwmctl command balance-sizes`). Found in 0.4.0 review. | Every written count change is followed by a Balance Sizes (§6.3). |
| License GPL-2.0. Icon used for a private, personal build. | OK for personal use; do not publish the repo with the icon without revisiting. |

---

## 3. Architecture

```
┌────────────────────────── OmniWM Extension.app ──────────────────────────┐
│  AppKit shell (NSStatusItem, NSMenu, HUD NSPanel w/ SwiftUI content)     │
│        ▲ renders AppState                    │ dispatches Command        │
│  ┌─────┴──────────┐   ┌──────────────┐   ┌───┴────────────┐              │
│  │ StateStore     │◄──│ OmniWMBridge │   │ CommandRunner  │──► HUD       │
│  │ (@Observable)  │   │ omniwmctl    │   └───┬────────────┘              │
│  │                │◄──│ SettingsWatch│       │                           │
│  │                │◄──│ DisplayWatch │       ▼                           │
│  └────────────────┘   └──────────────┘   SettingsEditor ──► settings.toml │
│  HotkeyManager (Carbon RegisterEventHotKey) ◄── ExtConfig ◄── config.toml │
└───────────────────────────────────────────────────────────────────────────┘
```

### 3.1 Project layout
```
omniwm-extension/
├── CLAUDE.md
├── CHANGELOG.md            # Keep a Changelog format
├── VERSION                 # single source of truth, e.g. 0.3.0
├── Makefile
├── project.yml             # XcodeGen spec (generated .xcodeproj is gitignored)
├── App/                    # AppKit/SwiftUI target (thin)
│   ├── Resources/          # AppIcon.icns, MenuBarIcon template PNGs, Info.plist
│   └── Sources/
├── Packages/Core/          # SwiftPM package, all logic, no AppKit
│   ├── Sources/Core/       # Config, SettingsEditor, HotkeyParser, PresetMatcher,
│   │                       # OmniWMModels, NDJSON parsing, DisplayPolicy
│   └── Tests/CoreTests/    # + Fixtures/ (real settings.toml, omniwmctl output)
├── scripts/
│   ├── create-signing-cert.sh
│   ├── fetch-icon.sh
│   └── release.sh
└── docs/PDR.md
```

- **Core is AppKit-free** so `swift test` runs fast. The app target is a thin shell.
- Project generated with **XcodeGen** (`brew install xcodegen`); the `.xcodeproj` is gitignored.
- `LSUIElement = YES` (no Dock icon, no app switcher entry).
- Dependency: **TOMLKit** (LebJe) for *parsing* `config.toml` and *reading* `settings.toml`. Writing `settings.toml` is done by our own line editor (§6.1). No other dependencies without Hans's approval.
- Logging: `os.Logger`, subsystem `com.omniwm.extension`, categories `bridge`, `settings`, `hotkeys`, `display`, `config`. Debug with `log stream --predicate 'subsystem == "com.omniwm.extension"'`.

### 3.2 State sources

| State | Source | Update trigger |
|---|---|---|
| Current workspace number + displayName | IPC `active-workspace` (+ `query workspaces` for `display-name` if missing) | event |
| Current workspace layout (Niri/Dwindle) | IPC `layout-changed` / `query workspaces` | event |
| Effective per-display gaps | IPC `display-changed` | event |
| Borders enabled | `settings.toml` `[borders] enabled` | file watch |
| Padding preset (name or Custom) | `settings.toml` `[gaps.outer]` matched against presets | file watch |
| Visible container count | `settings.toml` `[niri] visibleContainerCount` | file watch |
| Hyper modifiers, OmniWM hotkeys | `settings.toml` | file watch |
| Display topology (built-in only?) | `NSApplication.didChangeScreenParametersNotification` + `CGDisplayIsBuiltin` | notification |

**File watching:** a `DispatchSource` on the parent directory, not just the file, because editors and OmniWM save with an atomic rename that replaces the inode. Debounce 150 ms, then re-read and re-parse.

---

## 4. Extension config

Path: `~/.config/omniwm-extension/config.toml`. Respect `XDG_CONFIG_HOME` only if absolute, like OmniWM.

On first launch, if the file is missing, write the default below (with comments) and create the directory.

```toml
# OmniWM Extension config — saved changes apply immediately.

[general]
# Path to OmniWM settings. Empty = auto (${XDG_CONFIG_HOME:-~/.config}/omniwm/settings.toml)
omniwm_settings = ""
# On the built-in display alone (no external), switch padding to the first preset.
# When an external display returns, restore what it had before.
auto_fullscreen_on_builtin = true
# After changing visible containers, wait this long (ms) before telling OmniWM to
# Balance Sizes, so it has reloaded its settings first. Raise it if columns don't re-lay out.
balance_sizes_delay_ms = 120

[hud]
enabled = true
position = "center"      # center | top | bottom
duration_ms = 900

[hotkeys]
# Modifiers: ctrl, opt (alt), cmd, shift, hyper (= OmniWM's general.hyperKeyModifiers)
# Keys: a–z, 0–9, f1–f20, space, tab, return, escape, left, right, up, down,
#       minus, equal, comma, period, slash, semicolon, quote, backslash,
#       leftbracket, rightbracket, grave
# "" (or omitting the key) = unbound
cycle_padding        = "ctrl+opt+0"
toggle_borders       = "ctrl+opt+b"
visible_containers_1 = "hyper+1"
visible_containers_2 = "hyper+2"
visible_containers_3 = "hyper+3"
visible_containers_4 = "hyper+4"
visible_containers_5 = ""
visible_containers_6 = ""

# Padding presets. Order = cycle order. The FIRST preset is the one
# auto_fullscreen_on_builtin applies. Add, remove, or rename freely.
# Optional per preset: hotkey = "..."
[[padding]]
name = "Fullscreen"
top = 8
bottom = 8
left = 8
right = 8

[[padding]]
name = "Wide"
top = 540
bottom = 8
left = 8
right = 8

[[padding]]
name = "Single"
top = 720
bottom = 8
left = 640
right = 640
```

### 4.1 Validation rules
- `padding` must have ≥ 1 entry. Names are unique (case-insensitive) and non-empty. Values are numbers ≥ 0.
- Per-preset `hotkey` is optional (enables direct selection without the menu; empty by default).
- `hud.position` ∈ {center, top, bottom}; `duration_ms` clamped to 300–5000.
- `general.balance_sizes_delay_ms` clamped to 0–2000 (default 120).
- Hotkey strings: case-insensitive, `+`-separated, exactly one non-modifier key, at least one modifier. Unknown token → error naming the key and token.
- The same chord bound twice within our config → error.
- Unknown keys → warning (not error) to tolerate future fields.

### 4.2 Reload behavior
- Watched like `settings.toml` (§3.2). Valid → hotkeys re-registered, menu rebuilt, HUD "Config reloaded".
- **Invalid → keep the last good config running.** Show `⚠ Config error: <message> (line N)` at the top of the menu and a HUD "Config error — kept previous". If the very first load is invalid, run with built-in defaults and show the error.
- "Reload config" menu item forces a reload.

### 4.3 Hotkey conflicts
- `hyper` resolves from `settings.toml` `general.hyperKeyModifiers` (parse `Control|Option|Shift|Command` tokens). Re-resolve when that value changes.
- After resolution, compare each chord to every OmniWM `[[hotkeys]].binding` (skip `Unassigned`). On a match, show `⚠ ctrl+opt+b also bound in OmniWM (toggleX)` in the menu. Still register it; the user decides.
- If `RegisterEventHotKey` fails (chord taken by another app), show `⚠ Couldn't register <chord>` in the menu.
- Implementation: Carbon `RegisterEventHotKey`. No Accessibility permission needed, and none may be requested.

---

## 5. UI

### 5.1 Menu bar (status item)
Layout, left to right:

```
[icon] 1 - Code  |  ▢  |  Niri ●●●○
```

| Segment | Rule |
|---|---|
| icon | Monochrome **template** image derived from the OmniWM icon (adapts to light/dark). Fallback if it isn't legible at 18 pt: SF Symbol `rectangle.split.3x1`. Hans picks at the 0.1.0 review. |
| workspace | `#` if the workspace has no `displayName`, else `# - displayName`. |
| borders | SF Symbol `square` when enabled, `square.dashed` when disabled. |
| layout | `Niri` or `Dwindle`. |
| containers | Niri only. Count ≤ 4: filled dots = count, hollow up to 4 (`●●○○`). Count 5 or 6: text `5/6` / `6/6`. Hidden for Dwindle. |

- Separators are literal thin `|` in secondary label color. Use the monospaced-digit system font at menu bar size so the item doesn't jitter in width.
- **OmniWM not reachable** (not running, IPC disabled, `omniwmctl` missing): `[icon] —`. The borders segment still shows, since it comes from the file.
- Padding preset name is **not** in the menu bar (it's in the menu and HUD).

### 5.2 Menu (left click)
```
⚠ <warnings, if any: config error / hotkey conflicts / OmniWM not reachable / override notice>
─────
Padding                ▸   Cycle               ⌃⌥0
                           ─────
                           ✓ Fullscreen
                           Wide
                           Single
                           (Custom ✓, disabled — only when current gaps match no preset)
Visible containers     ▸   1  ⌃⌥⇧⌘1 … 6
Borders            ✓        ⌃⌥B
─────
Edit config file
Reload config
Start at login     ✓
─────
Restart
Quit                        ⌘Q
```
- Each item shows its configured hotkey as a key equivalent hint. "Cycle padding" is its own item at the top of the Padding submenu (`Cycle  ⌃⌥0`), followed by a separator and the presets. Presets with a `hotkey` show it.
- The "Visible containers" submenu shows ✓ on the current count. On a Dwindle workspace the items stay enabled; choosing one behaves like the hotkey (§6.3).
- **Edit config file:** open with the default app for `.toml`. If none is registered, open in TextEdit (`open -t`).
- **Start at login:** `SMAppService.mainApp` register/unregister; the checkmark reflects `.status`.
- **Restart:** relaunch **this app only** (spawn `/usr/bin/open -n <bundle path>` after a short delay, then terminate).
- **Quit:** terminate; the `omniwmctl` child process is killed too.

### 5.3 HUD
- Non-activating, borderless `NSPanel` (`.nonactivatingPanel`, `ignoresMouseEvents = true`, level `.statusBar`, joins all Spaces, works over full-screen apps), on the screen with the mouse cursor.
- Visual: `NSVisualEffectView` `.hudWindow` material, ~200×200 pt rounded (radius 18), large SF Symbol (~64 pt) over one line of text, like the macOS volume HUD.
- `top` position = just below the menu bar; `bottom` = ~140 pt above the bottom edge.
- Fade in 0.12 s, hold `duration_ms`, fade out 0.25 s. A new HUD replaces the current one immediately (no queue).
- Messages:

| Event | Symbol | Text |
|---|---|---|
| Padding set | `rectangle.inset.filled` | `Wide` |
| Padding auto on built-in | `laptopcomputer` | `Fullscreen · built-in` |
| Padding restored on dock | `display` | `Wide · restored` |
| Borders | `square` / `square.dashed` | `Borders on` / `Borders off` |
| Containers | `rectangle.split.3x1` | `3 containers` |
| Skipped on Dwindle | `exclamationmark.triangle` | `Dwindle — skipped` |
| Masked by override | `exclamationmark.triangle` | `Set, but this display overrides it` |
| Config reloaded / error | `checkmark.circle` / `xmark.octagon` | `Config reloaded` / `Config error — kept previous` |
| Write failure | `xmark.octagon` | `Couldn't write OmniWM settings` |

---

## 6. Behavior

### 6.1 Editing `settings.toml` (critical)
Port the semantics of the existing Perl scripts to Swift, then harden them:

1. Read the file fresh immediately before every edit (never from cache).
2. Locate the table header line exactly (`[gaps.outer]`, `[niri]`, `[borders]`). The table body runs until the next line starting with `[` or EOF.
3. Replace only the value of the target key line, preserving its indentation. If the key is missing inside an existing table, insert `key = value` as the first body line (matching the visible-columns script). If the table is missing → error (HUD + log); do not create tables.
4. Formatting: floats as `540.0` (OmniWM's style), integers as `3`, booleans as `true`/`false`.
5. Write atomically: temp file in the same directory → `rename(2)`. Preserve the original's permissions.
6. Lost-update guard: record mtime+size at read. If they changed before rename, re-read and re-apply once; if it fails again, error.
7. **Every other byte of the file must remain identical.** This is the primary property under test (golden-file tests using Hans's real `settings.toml` as fixture).
8. Edits are idempotent: a no-op change does not write the file.

### 6.2 Padding
- **Current preset detection:** compare `[gaps.outer]` top/bottom/left/right to each preset in order. A match means all four equal within 0.01. The first match wins. No match → `Custom`.
- **Select preset** (menu or per-preset hotkey): write the four values in one edit → HUD.
- **Cycle** (`cycle_padding`): next preset after the current one, wrapping around. From `Custom` → the first preset.
- Padding commands work regardless of workspace layout.

### 6.3 Visible containers
- Commands `visible_containers_1…6` write `[niri] visibleContainerCount = N`.
- **If the current workspace is Dwindle: do nothing, HUD `Dwindle — skipped`.**
- If OmniWM isn't reachable (layout unknown): apply the change and show the normal HUD.
- If N already equals the current count: no write, show the HUD anyway (confirmation).
- After a count change is written, wait `general.balance_sizes_delay_ms` (default 120 ms; OmniWM 0.7.6 reloads ~80 ms after a write) for OmniWM's live reload, then run `omniwmctl command balance-sizes` (resolved per §6.7, 2 s timeout, off the main thread). No write → no Balance Sizes. A failed Balance Sizes is logged; the write itself stands.

### 6.4 Borders
- `toggle_borders` flips `[borders] enabled` → HUD.

### 6.5 Display awareness (`auto_fullscreen_on_builtin`)
- **Built-in-only** = every active display satisfies `CGDisplayIsBuiltin`. **Docked** = at least one non-built-in display.
- On a topology change (debounced 1 s), and only when the topology differs from the last recorded one:
  - Docked → built-in-only: save the current `[gaps.outer]` values (exact numbers, so `Custom` round-trips) as `lastExternalGaps`, then apply the **first** preset → HUD `<name> · built-in`.
  - Built-in-only → docked: if `lastExternalGaps` exists, write it back → HUD `<name|Custom> · restored`.
- At launch, compare the current topology with the persisted `lastTopology`. Act only if it differs, so a relaunch never overrides a manual choice.
- While in either state, manual cycling and selection work normally and are never overridden until the next topology change.
- Persist `{ lastTopology, lastExternalGaps }` in `~/Library/Application Support/com.omniwm.extension/state.json`.
- Setting `false` → do nothing (still track topology so turning it on later doesn't fire spuriously).

### 6.6 Per-monitor overrides
- The app writes only global values. After a padding or containers command, check the active display: if a `[[monitorGapOverrides]]` row (for padding) or a `[[monitorNiriOverrides]]` row with `visibleContainerCount` (for containers) matches it (by `monitorDisplayUUID`, else `monitorDisplayId` + `monitorName`), show the override HUD and a persistent `ⓘ This display overrides <gaps|containers>` menu row.
- The menu bar container dots show the **effective** value for the active display (override if present, else global).

### 6.7 OmniWM bridge
- Resolve `omniwmctl`: `/Applications/OmniWM.app/Contents/MacOS/omniwmctl` → `~/Applications/...` → `PATH`.
- Spawn: `omniwmctl subscribe active-workspace,layout-changed,display-changed --reconnect --format ndjson`. Parse stdout line by line; ignore unknown kinds/channels; log and skip malformed lines.
- On the first connect and whenever `display-name` is needed but absent from the event, run `omniwmctl query workspaces --format json` (one-shot, 2 s timeout).
- Child exits (e.g. IPC disabled, OmniWM not installed) → mark unreachable, retry with backoff 1 s → 2 s → 5 s → 10 s (cap), reset on success.
- Never block the main thread on a child process.
- **Before writing the parsers, capture real output** from Hans's machine (`subscribe` initial snapshots + one live event per channel, `query workspaces`, `query displays`) into `Packages/Core/Tests/CoreTests/Fixtures/omniwm/`. Parsers are written against these fixtures, not the docs.

---

## 7. Signing, building, releasing

### 7.1 Self-signed identity (one-time)
`scripts/create-signing-cert.sh`:
- Creates a self-signed **code signing** certificate named `OmniWM Extension Self-Signed` (10-year validity, EKU codeSigning) with `openssl`, imports it with its key into the login keychain, and marks it trusted for code signing.
- Idempotent: exits 0 if the identity already exists (`security find-identity -v -p codesigning`).
- The same identity signs every build, so Login Items and any TCC state persist across updates.

### 7.2 Makefile targets
| Target | Does |
|---|---|
| `make gen` | `xcodegen generate` |
| `make test` | `swift test --package-path Packages/Core` + `xcodebuild test` (if the app target has tests) |
| `make build` | Release build, signed with the self-signed identity, hardened runtime on |
| `make run` | build + launch from `build/` |
| `make install` | build → quit the running app → replace `/Applications/OmniWM Extension.app` → relaunch |
| `make release VERSION=x.y.z` | see §7.3 |

- `MARKETING_VERSION` comes from the `VERSION` file. `CURRENT_PROJECT_VERSION` = `git rev-list --count HEAD`.
- `make build` ends with `codesign --verify --deep --strict` and `codesign -dv` (asserting the identity).

### 7.3 `make release VERSION=x.y.z` (`scripts/release.sh`)
Aborts on any failed precondition:
1. On `main`, clean tree, in sync with `origin/main`.
2. `VERSION` is valid SemVer and greater than the latest tag.
3. `CHANGELOG.md` has a `## [x.y.z] - YYYY-MM-DD` section. Its body becomes the release notes.
4. `make test` passes.
5. Write `VERSION`, commit `chore(release): vX.Y.Z`, tag `vX.Y.Z` (annotated).
6. `make build` → `ditto -c -k --keepParent` → `OmniWM-Extension-X.Y.Z.zip` + `.sha256`.
7. `git push origin main --follow-tags`.
8. `gh release create vX.Y.Z <zip> <sha256> --title "vX.Y.Z" --notes-file <extracted notes>`.

**Updating on Hans's Mac:** `make install` from the repo, or `gh release download vX.Y.Z -R hanswug/omniwm-extension`, unzip, `xattr -dr com.apple.quarantine`, then move to `/Applications`. Document both in the README.

### 7.4 Icon
`scripts/fetch-icon.sh` extracts the OmniWM app icon from `/Applications/OmniWM.app/Contents/Resources/` (the `.icns` if present; otherwise from `Assets.car` via `assetutil`/`iconutil`) into `App/Resources/AppIcon.icns`, and generates monochrome template PNGs (`MenuBarIcon.png` @1x 18 pt, @2x) from the icon's alpha silhouette. Commit the outputs, so builds don't depend on OmniWM being installed.

---

## 8. Tasks

Each task follows CLAUDE.md: branch → implement → automated tests → Hans runs the manual checklist and approves → merge → push → release. Acceptance criteria (**AC**) must all hold before asking for approval.

### 0.1.0 — Skeleton & release pipeline
Branch `feat/skeleton`
- Create the private repo (`gh repo create hanswug/omniwm-extension --private`), commit `docs/PDR.md`, `CLAUDE.md`, `.gitignore`, `CHANGELOG.md`, `VERSION`.
- XcodeGen project, Core package with one trivial test, `LSUIElement` app showing the icon in the menu bar.
- Menu: Edit config file (opens the path even if the file doesn't exist yet — create an empty placeholder dir/file), Start at login, Restart, Quit.
- `create-signing-cert.sh`, `fetch-icon.sh`, Makefile, `release.sh`.

**AC:** `make test`, `make build`, and `make install` succeed. `codesign -dv` shows the self-signed identity. `make release VERSION=0.1.0` produces a GitHub release with zip + sha256.
**Manual check:** icon visible in light and dark mode (Hans picks template vs SF Symbol fallback) · Start at login toggles, survives a logout/login · Restart relaunches · Quit quits · no Dock icon.

### 0.2.0 — Extension config
Branch `feat/config`
- Config model, defaults file writer, TOMLKit parsing, validation (§4.1), file watch + reload (§4.2), warnings section in the menu, Reload config item.

**AC:** unit tests for: default round-trip, every validation rule, hotkey-string parsing (valid/invalid/unbound), last-good-config retention.
**Manual check:** first launch creates a commented default · break the file → menu shows the error with its line, app keeps working · fix it → warning clears.

### 0.3.0 — Settings editor & hotkeys
Branch `feat/settings-editor-hotkeys`
- `SettingsEditor` (§6.1), `SettingsReader` (borders, gaps, count, hyper, OmniWM hotkeys, overrides, workspaces' displayName), settings file watch.
- `HotkeyManager`: Carbon registration, `hyper` resolution, conflict detection (§4.3). Wire hotkeys to log-only stub actions.

**AC:** golden-file tests on Hans's real `settings.toml` fixture: each edit changes only the target line; missing key inserted; missing table errors; float/int/bool formatting; no-op does not write; concurrent-modification retry. Hyper parsing tests. Conflict detection tests.
**Manual check:** each configured chord logs its action (`log stream`) · binding a known OmniWM chord shows the conflict warning · set a hotkey to `""` → it stops firing.

### 0.4.0 — Commands
Branch `feat/commands`
- Padding select/cycle (§6.2), visible containers 1–6 (§6.3, Dwindle check stubbed as "unknown → apply" until 0.6.0), borders toggle (§6.4). Menu: Padding submenu with Cycle + presets + Custom, Visible containers submenu, Borders item, hotkey hints.

**AC:** preset matcher tests (exact, tolerance, Custom, first-match-wins); cycle order including from Custom and wrap-around.
**Manual check:** ctrl+opt+0 cycles Fullscreen → Wide → Single → Fullscreen and OmniWM visibly re-lays out · hand-edit gaps → menu shows Custom; cycling goes to Fullscreen · hyper+1…4 change columns · ctrl+opt+b toggles borders · add a 4th preset and rename one → appears in menu and cycle without restart.

### 0.5.0 — HUD
Branch `feat/hud`
- HUD panel per §5.3, wired to every command and to config reload/error.

**AC:** HUD never takes focus (typing in the frontmost app is uninterrupted), never intercepts clicks, appears on the screen with the cursor, over full-screen apps, replaces itself on rapid presses.
**Manual check:** hammer ctrl+opt+0 while typing in an editor · test all three positions · `hud.enabled = false` disables it.

### 0.6.0 — OmniWM bridge & live menu bar
Branch `feat/omniwm-bridge`
- Capture fixtures first (§6.7). NDJSON parser, subscription process with reconnect/backoff, `query workspaces`. Menu bar rendering per §5.1. Real Dwindle check for containers (§6.3). Override detection and effective container count (§6.6). Unreachable state.

**AC:** parser tests against the captured fixtures (incl. malformed line, unknown channel). Menu bar formatter tests for every segment (displayName present/absent, Niri 1–6, Dwindle, unreachable).
**Manual check:** switching workspaces updates the label instantly · `displayName` shows `# - Name` · toggle a workspace to Dwindle → dots disappear; hyper+2 shows "Dwindle — skipped" · quit OmniWM → `—`; relaunch → recovers by itself · turn IPC off/on in OmniWM → same.

### 0.7.0 — Display awareness
Branch `feat/display-awareness`
- §6.5 in full, plus persisted state.

**AC:** `DisplayPolicy` unit tests (pure function: previous topology, new topology, current gaps, setting → action), including launch-without-change, Custom round-trip, and setting disabled.
**Manual check:** docked on Wide → close/disconnect to built-in → Fullscreen + HUD · cycle to Single on the laptop → re-dock → Wide restored · relaunch the app in each state → nothing changes · setting false → nothing happens.

### 1.0.0 — Hardening & README
Branch `chore/hardening`
- README (install, signing script, config reference, update paths, troubleshooting with `log stream`). Leak/zombie check on the `omniwmctl` child across reconnects. Main-thread audit. Stress test: 100 rapid cycle presses → file valid, final state consistent.

**AC:** all tests green; `settings.toml` intact after the stress test (diff only in the 4 gap lines).
**Manual check:** one full day of normal use without issues → Hans approves 1.0.0.

---

## 9. Risks & mitigations

| Risk | Mitigation |
|---|---|
| OmniWM writes `settings.toml` while we do → lost update | Fresh read, mtime+size guard, single retry, atomic rename (§6.1). |
| OmniWM upgrade rewrites/reorders the file | The editor locates tables and keys by content, not position. |
| `omniwmctl` JSON shapes change | Parsers built on captured fixtures and tolerant of unknown fields; on parse failure, degrade to "unreachable" rather than crash. Re-capture fixtures after OmniWM updates. |
| OmniWM adds native commands for gaps/borders/columns | Revisit: prefer IPC over file edits. Note in CHANGELOG. |
| Self-signed app blocked by Gatekeeper after download | Install via `make install`, or strip quarantine (documented). |
| Hotkey taken by another app | Registration failure surfaced in the menu (§4.3). |
