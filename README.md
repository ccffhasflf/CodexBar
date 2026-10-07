# CodexBar Lite

A small macOS menu bar app for **Codex subscription quota, reset times and multiple accounts**.
Derived from [steipete/CodexBar](https://github.com/steipete/CodexBar), baseline `8ab81e2eb` (2026-10-07),
with upstream Git history and MIT license retained.

## Included

- Menu bar remaining percentage; 5-hour, weekly, monthly and additional model quota windows when supplied by the service.
- Exact reset dates and countdowns. Expired windows are not assumed to have refilled before the next successful request.
- Independent accounts, browser login, account labels, removal and selection within Lite.
- Read-only links to existing native Codex `auth.json` homes.
- Refresh every 1, 5, 15 or 30 minutes, manual refresh, wake refresh and optional launch at login.
- Simplified Chinese UI. macOS 14+, Swift 6.2+, no third-party runtime dependencies.

There is no local token/cost scanning, transcript index, cost database, history chart, WebKit,
browser-cookie access, other provider, widget, plugin, cloud sync, hook or standalone CLI product.
Lite does not change which account the Codex App or Codex CLI is using.

## Use

Open **CodexBar Lite.app**, choose **设置** in its menu, then:

1. **添加账号…** opens a Codex browser login in an isolated home. A local Codex CLI is required only for this step.
   The Homebrew installation and the Codex desktop app's bundled executable are detected where available;
   use **Codex 登录工具 → 选择…** if your installation is elsewhere.
2. Or use **关联现有登录** to select your existing Codex home containing `auth.json`.
3. Select an account in the menu to view its quota. The percentage means **remaining**, not used.

Independent login credentials live in `~/Library/Application Support/CodexBarLite/accounts/<UUID>/auth.json`;
configuration lives beside `accounts` in `config.json`. Rotated tokens are written atomically with `0600` permissions.
Linked homes remain read-only and their refresh tokens are never rotated by Lite. If a linked login expires,
reauthenticate in its owning Codex app or add an independent account. Keychain-only and API-key logins are not supported.
Removing an independent account deletes its Lite-owned home; removing a link only unlinks it.

Install the bundle in Applications before enabling launch at login. This personal build is ad-hoc signed,
not Developer ID notarized. It has a separate bundle identifier and no upstream auto-updater.

## Build and validate

```sh
make check     # pinned upstream SwiftFormat + SwiftLint (first run downloads these development tools)
make test      # offline fixtures and fake login processes only
make package   # .build/CodexBar Lite.app, release build + ad-hoc signature verification
open '.build/CodexBar Lite.app' --args --demo
```

`--demo` uses an in-memory sample account; it does not read actual credentials, call the usage service,
write account configuration or enable launch at login. Quit the demo before opening the app normally.
Tests cover quota parsing, account isolation, token rotation, non-overlapping refresh, cancellation,
login subprocess cleanup and 10,000 refresh rounds retaining only the latest snapshots.

## Memory and maintenance

One ephemeral URLSession, no cookie jar or response cache. Refreshes are serialized and coalesced.
Only one current snapshot/error per account is retained. Login capture is limited to 32 KiB and exists only
while login is running. Timers pause during sleep; quota countdowns redraw while their view is mounted.
These choices remove the old high-memory workloads, but a short demo run does not prove multi-day stability.
Live login/API compatibility and extended real-account operation must be validated separately.

`Sources/CodexBarLiteCore` owns data and refresh state; `Sources/CodexBarLite` owns the UI and browser-login subprocess.
Quota response decoding, spend-limit numeric normalization, credential conventions and private file publication
are adapted from upstream. Future upstream changes should be reviewed and selectively ported rather than blindly
merging the full multi-provider application back into this fork.
