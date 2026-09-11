# Native Menu-Bar Companion Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Add a macOS-native menu-bar companion that shows saved Codex profiles and safely switches them by invoking the existing `codex-account` CLI, without reading or storing credentials.

**Architecture:** A standalone Swift Package executable, `codex-account-menu`, creates an `NSStatusItem` menu-bar icon. It invokes the `codex-account` executable using `Process(executableURL:arguments:)`, requests only a new redacted JSON profile listing, and passes a selected validated profile name back as a distinct process argument. The Bash credential engine remains the only component that reads or writes OAuth credentials.

**Tech Stack:** Bash 3.2 core; Swift 6 + AppKit (`NSStatusItem`) companion; XCTest-compatible Swift tests; no third-party packages; no network access, Keychain access, LAN listener, OAuth flow, or credential export.

**Security invariants:**
- The menu app must never read `~/.codex/auth.json` or profile files.
- The CLI JSON response must never contain tokens, account IDs, credential paths, or raw session content.
- The menu app must execute the CLI directly with `Process`, never through a shell.
- UI operations must use only `list --json` and `use <validated-profile-name>`.
- The app must not request Accessibility, automation, admin, network, or filesystem permissions.

---

### Task 1: Add safe JSON listing to the CLI

**Objective:** Expose profile name, display email, active state, and optional local usage label without exposing secrets.

**Files:**
- Modify: `bin/codex-account`
- Modify: `tests/cli.bats`

**Step 1: Write failing tests**

Add Bats tests for `list --json` asserting:
- valid JSON output;
- exactly safe fields `name`, `email`, `active`, and optional `usage`;
- no refresh-token, id-token, API-key, account-id, or filesystem path values;
- profile names with control bytes cannot occur due to current validation.

**Step 2: Run test to verify failure**

Run: `bats tests/cli.bats`

**Step 3: Implement minimal output mode**

Add a `--json` option valid only for `list`. Generate JSON with shell-safe escaping using the existing `jq` path; JSON mode must fail with a clear install message when `jq` is unavailable. Preserve the existing human-oriented default output exactly, including its legacy no-`jq` fallback behavior.

**Step 4: Run tests**

Run: `bats tests/cli.bats tests/safety.bats`

**Step 5: Commit**

```bash
git add bin/codex-account tests/cli.bats
git commit -m "feat: add redacted profile list JSON"
```

### Task 2: Create and test a safe Swift CLI bridge

**Objective:** Create tested Swift code that invokes the credential CLI directly and decodes only its safe JSON contract.

**Files:**
- Create: `menu-bar/Package.swift`
- Create: `menu-bar/Sources/CodexAccountMenu/CLIClient.swift`
- Create: `menu-bar/Tests/CodexAccountMenuTests/CLIClientTests.swift`

**Step 1: Write failing XCTest cases**

Test:
- decoding a valid redacted profile list;
- rejection of unexpected/missing fields;
- command construction uses an executable URL and individual arguments;
- `use` rejects an invalid profile name before process launch;
- failure output is converted to a bounded user-visible error without echoing possible sensitive content.

**Step 2: Run test to verify failure**

Run: `swift test --package-path menu-bar`

**Step 3: Implement `CLIClient`**

Define a `CodexAccountProfile` with only `name`, `email`, `active`, `usage`. Locate the CLI through an explicit config/default path; execute `list --json` and `use <name>` using `Process`. Validate names using the same `[A-Za-z0-9][A-Za-z0-9._-]{0,63}` policy before execution. Never use `/bin/sh`, `bash -c`, `NSTask` string commands, or token-file paths.

**Step 4: Run tests**

Run: `swift test --package-path menu-bar`

**Step 5: Commit**

```bash
git add menu-bar
git commit -m "feat: add safe menu companion CLI bridge"
```

### Task 3: Implement the menu-bar UI

**Objective:** Present profiles in a native status-item menu and allow switching with clear progress/error states.

**Files:**
- Create: `menu-bar/Sources/CodexAccountMenu/AppDelegate.swift`
- Create: `menu-bar/Sources/CodexAccountMenu/main.swift`
- Create: `menu-bar/README.md`

**Step 1: Add testable menu-model behavior**

Add unit tests for ordering active profile first, rendering inactive profiles as selectable items, disabling concurrent switches, and mapping errors to redacted messages.

**Step 2: Implement AppKit status item**

- Create an `NSStatusItem` with a neutral icon/title.
- Populate it from `list --json` on launch and menu open.
- Show active account with a checkmark.
- Disable the menu while a switch is running.
- Call the existing CLI to switch; then reload list data.
- Include `Refresh`, `Open Codex`, and `Quit Menu` commands only if each can be implemented without expanding credential access.

**Step 3: Build/run verification**

Run: `swift build --package-path menu-bar` and `swift test --package-path menu-bar`.

**Step 4: Document limitations**

Document that this is a local menu wrapper, does not make network calls, does not store tokens, and requires `codex-account` on PATH or a configured absolute executable path.

**Step 5: Commit**

```bash
git add menu-bar
git commit -m "feat: add native macOS menu-bar companion"
```

### Task 4: End-to-end quality gate

**Objective:** Verify core and companion behavior together without using real credentials.

**Files:**
- Modify: `README.md`
- Modify: `CONTRIBUTING.md` if developer prerequisites change

**Steps:**
1. Run the complete Bats suite.
2. Run `bash -n bin/codex-account`, `shellcheck` and `shfmt` if available.
3. Run `swift test --package-path menu-bar` and `swift build --package-path menu-bar`.
4. Inspect `git diff --check` and verify there is no network client, token path, credential-file read, server listener, or shell command construction in `menu-bar/`.
5. Update README with build/run instructions and threat-model boundaries.
6. Commit the final documentation and verification changes.
