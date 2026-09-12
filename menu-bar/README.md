# Codex Account Menu

`codex-account-menu` is a minimal macOS menu-bar wrapper around the existing `codex-account` CLI.

It only runs:

- `codex-account list --json`
- `codex-account use <profile>`

The app does not read auth, profile, token, or session files. It does not make network calls, store credentials, start a listener, or request Accessibility, automation, admin, or filesystem permissions.

## Build

```sh
swift build --package-path menu-bar
swift test --package-path menu-bar
```

## Run

By default the app uses the first executable CLI found at `$HOME/.local/bin/codex-account`, `/opt/homebrew/bin/codex-account`, or `/usr/local/bin/codex-account`. To use a different absolute path:

```sh
CODEX_ACCOUNT_EXECUTABLE=/absolute/path/to/codex-account swift run --package-path menu-bar codex-account-menu
```

The menu refreshes when opened, shows each profile's available five-hour and weekly limits, marks the active profile with a checkmark, and reloads after switching. It also saves the current sign-in, signs out locally to begin adding another account, and removes inactive saved accounts without requiring Terminal.

OpenAI authentication still happens in Codex itself. “Sign Out to Add Account…” preserves the current saved profile, restarts Codex at its login screen, and lets the user save the new sign-in from the menu after authentication succeeds.
