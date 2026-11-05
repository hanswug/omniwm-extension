# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-11-04

### Added
- Menu bar app skeleton (`LSUIElement`, no Dock icon) with a template icon derived from the OmniWM icon.
- Menu: Edit config file (creates an empty `config.toml` placeholder if missing), Start at login, Restart, Quit.
- `Core` Swift package with config/app-support path resolution (`XDG_CONFIG_HOME` honoured only if absolute) and loggers.
- XcodeGen project, Makefile (`gen`, `test`, `build`, `run`, `install`, `release`).
- Scripts: `create-signing-cert.sh`, `fetch-icon.sh`, `release.sh`.
