# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- With OmniWM Dev, a visible-containers change is no longer followed by Balance Sizes: Dev re-lays out by itself, using its own "When Visible Containers Change" setting (Balance Sizes or Reset Layout). The release still gets Balance Sizes.

## [1.0.3] - 2026-11-05

### Added
- The app follows whichever OmniWM is running. While OmniWM Dev (built with `make run` in an OmniWM checkout) runs, it uses Dev's own `omniwmctl` and `~/.config/omniwm-dev/settings.toml`, so padding, visible containers, borders, Balance Sizes and the live menu bar work with Dev. When Dev quits, it switches back to the release. An explicit `general.omniwm_settings` still wins.

### Fixed
- With OmniWM Dev running, every `omniwmctl` call failed with a protocol mismatch, because the release's `omniwmctl` was always used, and settings edits went to the release's file.

## [1.0.2] - 2026-11-05

### Fixed
- The menu bar showed `FC` all the time on 1 visible container, because every column fills the width there. `FC` now also requires an effective visible container count of at least 2 (per-display overrides count). Changing the count no longer fires a "Full container on/off" HUD.

## [1.0.1] - 2026-11-05

### Changed
- The minimum macOS is now 26.0 (was 27.0), so the app runs on Macs still on macOS 26.x. The build no longer uses any API that needs 27, and every system library it requires also ships on 26. Builds stay Apple Silicon only (`ARCHS = arm64`).

## [1.0.0] - 2026-11-05

### Fixed
- OmniWM allows at most **5** visible containers, not 6 (the PDR was wrong):
  - commands and the menu go 1–5;
  - the menu bar shows `5/5` for five;
  - the default config no longer has `visible_containers_6`. An existing one is ignored when empty and a warning when bound.

### Added
- README: install (source and release), signing script, update paths, config reference, how the app touches OmniWM, troubleshooting with `log stream`, development.
- Stress tests on a copy of the real `settings.toml`:
  - 100 rapid cycles change only the gap lines and end on the right preset;
  - 100 cycles while a simulated OmniWM rewrites another key every 20 ms: the file stays valid, the gaps are never torn, and OmniWM's last write always survives;
  - 4 × 25 unserialized concurrent cycles never tear the gaps.

### Changed
- Hardening checks, no code changes needed:
  - 45 forced reconnects of the `omniwmctl` child leave exactly one child, no zombies, stable file descriptors and flat memory;
  - main-thread audit: all file and process I/O runs off the main thread, and a sample under load showed the main thread 98 % idle.

## [0.7.1] - 2026-11-05

### Changed
- Menu bar: the layout segment is an icon instead of text, like OmniWM's layout picker: `rectangle.split.3x1` for Niri (followed by the container dots) and `rectangle.split.2x2` for Dwindle. VoiceOver still reads "Niri" / "Dwindle".
- The Dwindle layout HUD uses the same `rectangle.split.2x2` icon.

## [0.7.0] - 2026-11-05

### Added
- Display awareness (`general.auto_fullscreen_on_builtin`, PDR §6.5). When docked turns into built-in only, the current `[gaps.outer]` is saved with its exact numbers and the first preset is applied (HUD `<name> · built-in`). When an external display returns, the saved gaps are written back (HUD `<name|Custom> · restored`).
- Topology changes are debounced 1 s, and nothing happens unless the topology actually changed. A relaunch compares against `state.json` (`lastTopology`, `lastExternalGaps`), so it never overrides a manual choice. With the setting off, the topology is still tracked. The very first run only records.

## [0.6.0] - 2026-11-05

### Added
- Live menu bar title per PDR §5.1: `1 - Code  |  ▢  |  Niri ●●○○`. It shows the workspace number and custom name, the borders symbol, the layout, and the effective container dots (`5/6` / `6/6`, hidden on Dwindle). When OmniWM isn't reachable it shows `—` and keeps the borders segment, and the menu warns "OmniWM not reachable".
- OmniWM bridge: a long-lived `omniwmctl subscribe` child process with reconnect backoff 1/2/5/10 s. It's killed on quit, including on SIGTERM. Parsers are written against captured fixtures.
- OmniWM toggle feedback (PDR §6.8): HUDs for OmniWM's own `toggle-fullscreen` (`Fullscreen on/off`), `toggle-workspace-layout` (`Niri` / `Dwindle`) and `toggle-container-full-primary-span` (`Full container on/off`), however they're triggered. The menu bar shows `F` while the focused window is fullscreen and `FC` while it's a full container. IPC has no command events, and leaving OmniWM fullscreen emits none at all, so the bridge re-queries the focused window after events and also polls it (every 0.5 s while `F`/`FC` is shown, otherwise every 1.5 s).
- The Dwindle check for visible containers now uses the real layout: `Dwindle — skipped`.
- Per-display overrides (PDR §6.6): the HUD says `Set, but this display overrides it`, a `ⓘ This display overrides gaps/containers` row appears in the menu, and the dots show the effective count.

## [0.5.0] - 2026-11-05

### Added
- HUD per PDR §5.3: a borderless, non-activating, click-through panel at status-bar level that joins all Spaces and shows over full-screen apps, on the screen with the cursor. HUD-material blur, rounded 18 pt, a large SF Symbol over one line of text. Fades in 0.12 s, holds `hud.duration_ms`, fades out 0.25 s, and a new HUD replaces the current one immediately.
- HUD for every command (preset name, `N containers`, `Borders on/off`, `Dwindle — skipped`, `Couldn't write OmniWM settings`) and for config reloads (`Config reloaded`, `Config error — kept previous`, `Config error — using defaults`). `hud.position` (center/top/bottom) and `hud.enabled` are honoured.

### Changed
- The menu row for a failed command now appears only while the HUD is disabled.

## [0.4.0] - 2026-11-05

### Added
- Padding: select a preset (menu or per-preset hotkey) and `cycle_padding` (next preset, wraps; from Custom goes to the first). The current preset is matched within 0.01 on all four edges; the first match wins, otherwise Custom.
- Visible containers 1–6 (`[niri] visibleContainerCount`). The Dwindle check treats the layout as unknown and applies until the OmniWM bridge lands. A written count change is followed by `omniwmctl command balance-sizes`, because OmniWM only re-lays out existing columns after Balance Sizes. The wait before it is configurable as `general.balance_sizes_delay_ms` (default 120, clamped to 0–2000).
- Borders toggle (`[borders] enabled`).
- Menu: Padding submenu (Cycle, presets, Custom), Visible containers submenu and Borders, with checkmarks from `settings.toml` and the registered hotkeys as key-equivalent hints.
- Commands run one at a time off the main thread. Each decides from a fresh read inside the atomic edit, so a retry after a concurrent change re-decides. Failures show in the menu until the next command succeeds.

## [0.3.0] - 2026-11-04

### Added
- `SettingsEditor`: surgical edits of OmniWM's `settings.toml` per PDR §6.1. It changes only the target value token, inserts a missing key as the first body line, errors on a missing table, writes atomically with permissions preserved, follows symlinks, retries once on concurrent modification, and skips no-op writes. Golden-file tests run on a copy of the real `settings.toml`.
- `SettingsReader`: borders, outer gaps, visible container count, hyper modifiers, OmniWM hotkeys, monitor overrides and workspace display names. The settings file is watched live.
- Global hotkeys via Carbon `RegisterEventHotKey` (no permissions needed); `hyper` resolves from `general.hyperKeyModifiers`. Actions are log-only stubs for now.
- Menu warnings: chords also bound in OmniWM, chords that collide after resolving `hyper`, failed registrations, and unreadable OmniWM settings.
- `general.omniwm_settings` is honoured (`~/` expanded; relative paths are a config error).

### Fixed
- Config error line numbers were wrong for files with CRLF line endings.

## [0.2.0] - 2026-11-04

### Added
- Extension config at `${XDG_CONFIG_HOME:-~/.config}/omniwm-extension/config.toml`; the commented default is written on first launch.
- Config validation per PDR §4.1 with line numbers: presets, HUD settings, hotkey strings, duplicate chords. Unknown keys are warnings; out-of-range `duration_ms` is clamped with a warning.
- Live reload on save (watches the file and its directory, 150 ms debounce). An invalid config keeps the last good one running; an invalid first load runs built-in defaults.
- Menu: warnings section and "Reload config".
- Dependency: TOMLKit 0.6.0.

### Changed
- "Edit config file" writes the commented default (instead of an empty file) when the config is missing or blank.

## [0.1.0] - 2026-11-04

### Added
- Menu bar app skeleton (`LSUIElement`, no Dock icon) with a template icon derived from the OmniWM icon.
- Menu: Edit config file (creates an empty `config.toml` placeholder if missing), Start at login, Restart, Quit.
- `Core` Swift package with config/app-support path resolution (`XDG_CONFIG_HOME` honoured only if absolute) and loggers.
- XcodeGen project, Makefile (`gen`, `test`, `build`, `run`, `install`, `release`).
- Scripts: `create-signing-cert.sh`, `fetch-icon.sh`, `release.sh`.
