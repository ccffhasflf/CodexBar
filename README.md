# CodexBar Lite

A small macOS menu bar app that **follows the currently logged-in Codex account** and displays its
subscription quota and reset times. Derived from [steipete/CodexBar](https://github.com/steipete/CodexBar),
baseline `8ab81e2eb` (2026-10-07), with upstream Git history and MIT license retained.

## Use

Open **CodexBar Lite.app**. It immediately reads `auth.json` in `CODEX_HOME`, or `~/.codex` if that
variable is absent. No account setup, separate login or Codex CLI executable is required.
If you use another Codex home, select it in **设置 → Codex → 认证**. macOS GUI apps may not inherit
terminal environment variables, so choosing the directory explicitly is useful for custom homes.

The original Codex two-meter menu bar icon shows **remaining** quota. Click for 5-hour, weekly, monthly and additional
model windows supplied by the service, plus countdowns (hover a quota row for its exact reset date). Refresh manually or
every 1, 5, 15 or 30 minutes. Optional launch at login is available in Settings.

When Codex changes its auth file, Lite clears the previous account's display, cancels its pending
request and reads the current login again. File and directory events handle in-place writes, atomic
replacement, logout/deletion and later login. A short debounce combines events from a single write;
there is no high-frequency polling or transcript scan.

The auth file is read-only. Lite does not save account copies, modify it, rotate its refresh token,
or switch the Codex App/CLI login. If it expires, reauthenticate in Codex. Keychain-only and API-key
logins are not supported. The previous version's managed accounts are preserved on disk but are not
used by this version; any old selection is ignored in favor of the current native login.

## Interface

The native NSMenu, 310pt quota card, 6pt progress bars, Codex icon geometry, and 880×620 settings
sidebar retain upstream CodexBar styling. Settings keep General, Codex and About; removed features
do not leave empty tabs. Upstream settings materials, sizing, sidebar resize handle and metric-header
layout are reused. `--settings` opens Settings at launch for UI verification.

## Scope

Only Codex quota, resets, current-account following and basic settings. No local cost/token scanning,
transcript index, database, history chart, WebKit, browser cookies, other provider, widget, plugin,
cloud sync, hook, independent login flow or standalone CLI product. Simplified Chinese UI, macOS 14+,
Swift 6.2+, no third-party runtime dependencies.

Future account switching is intentionally deferred. The intended workflow is to save account auth
files, restore the selected one, then let the user manually restart Codex. No automatic app restart
or live-process account promotion is planned.

## Build and validate

```sh
make check     # pinned upstream SwiftFormat + SwiftLint
make test      # offline fixtures only; no real credential reads or network calls
make package   # .build/CodexBar Lite.app, release build + ad-hoc signature verification
open '.build/CodexBar Lite.app' --args --demo --settings
```

`--demo` uses in-memory sample quota, skips file monitoring, and does not read real credentials,
call the usage service, save configuration or enable launch at login. Quit before opening normally.
Tests cover quota parsing, read-only linked credentials, file replacement/deletion/recreation,
ignoring legacy account selection, late responses after account changes, coalescing and cancellation.

Install in Applications before enabling launch at login. This personal build is ad-hoc signed,
not Developer ID notarized. It has its own bundle ID and no upstream auto-updater. Settings are in
`~/Library/Application Support/CodexBarLite/config.json`.

## Memory and maintenance

One ephemeral URLSession with no response cache or cookies. Refresh requests are coalesced; only
current snapshots are retained. File monitoring uses at most two event sources and one debounce task.
Timers pause during sleep. The v0.1 acceleration measurements cover the previous build, not this
version's newly added file-monitor lifecycle; they are not a promise of multi-day real-world stability.

`Sources/CodexBarLiteCore` owns quota data, credentials, refresh state and file monitoring;
`Sources/CodexBarLite` owns the native UI and lifecycle. Upstream decoding and credential conventions
are retained. Future upstream fixes should be selectively ported rather than merging the complete
multi-provider app back in.
