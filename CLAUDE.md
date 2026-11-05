# CLAUDE.md — OmniWM Extension

Native Swift menu bar app extending the OmniWM window manager. **The spec is `docs/PDR.md`. Read it fully before starting any task.** If code and the PDR disagree, the PDR wins; if the PDR is wrong or silent, stop and ask Hans. Don't guess.

## Working rules

- **One task at a time**, in the order of PDR §8. Never start the next task until the current one is released.
- Hans is the **only approver**. You never merge without his explicit "approved" for that task.
- No new dependencies beyond TOMLKit without asking.
- Never request Accessibility, Input Monitoring, or other TCC permissions.
- Never commit secrets, certificates, or private keys. The signing identity lives only in the login keychain.
- Never modify Hans's real `~/.config/omniwm/settings.toml` from tests. Tests use fixture copies in a temp dir. Manual verification against the real file happens only through the running app.

## Task workflow

For each task in PDR §8:

1. **Branch** from up-to-date `main`: `git switch main && git pull && git switch -c <branch from PDR>`.
2. **Implement** in small, coherent commits. Conventional Commits: `feat:`, `fix:`, `test:`, `refactor:`, `chore:`, `docs:`.
3. **Test:** `make test` must be green, and every AC in the task must hold. Add tests for every AC that is testable in code.
4. **Changelog:** add the task's entries under `## [Unreleased]` in `CHANGELOG.md` (Keep a Changelog: Added / Changed / Fixed).
5. **Request approval.** Push the branch, `make install` so the build is running locally, then post to Hans:
   - what changed (short),
   - test summary,
   - the task's **manual checklist** from the PDR as checkboxes,
   - anything deviating from the PDR, with the reason.

   Then **stop and wait**.
6. **On "approved":**
   - Rename `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD` and add a fresh empty `## [Unreleased]`, committed on the branch.
   - Merge into `main` with `git merge --no-ff <branch>`, push `main`, delete the branch locally and on the remote.
   - `make release VERSION=X.Y.Z`.
   - Report the release URL.
7. **On feedback:** fix on the same branch and go back to step 3.

### Versioning
- Each task's version is listed in PDR §8.
- A fix between tasks (after a release, before the next task starts) uses branch `fix/<slug>` and a patch bump (e.g. 0.4.1). Same approval flow.
- The `VERSION` file is the single source of truth. `release.sh` writes it; don't bump it by hand.

## Commands

```bash
make gen          # regenerate Xcode project (after editing project.yml)
make test         # Core unit tests (+ app tests)
make build        # signed release build into build/
make run          # build and launch
make install      # replace /Applications/OmniWM Extension.app and relaunch
make release VERSION=x.y.z
log stream --predicate 'subsystem == "com.omniwm.extension"'   # live logs
```

## Code conventions

- Swift 6, strict concurrency. All logic lives in `Packages/Core` (no AppKit import there). The app target is a thin shell.
- AppKit for the status item, menu and HUD panel; SwiftUI is allowed inside the HUD content.
- No force unwraps outside tests. Errors are typed and surface to the user through the menu warnings or the HUD, per the PDR.
- Never block the main thread on I/O or child processes.
- `settings.toml` edits go **only** through `SettingsEditor`. It must leave every byte it doesn't target identical (PDR §6.1).
- OmniWM output parsers are written against **captured fixtures** in `Packages/Core/Tests/CoreTests/Fixtures/omniwm/`, not against the docs.

## Environment facts

- OmniWM settings: `${XDG_CONFIG_HOME:-~/.config}/omniwm/settings.toml`
- Extension config: `${XDG_CONFIG_HOME:-~/.config}/omniwm-extension/config.toml`
- App state: `~/Library/Application Support/com.omniwm.extension/state.json`
- `omniwmctl`: `/Applications/OmniWM.app/Contents/MacOS/omniwmctl`
- Signing identity: `OmniWM Extension Self-Signed`
- Repo: `hanswug/omniwm-extension` (private). Target macOS 26.0+ (work Mac runs 26.x).
