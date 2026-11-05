# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
