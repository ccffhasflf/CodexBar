# CodexBar Lite

A small macOS menu bar app that **follows the currently logged-in Codex account** and displays its
subscription quota and reset times. Derived from [steipete/CodexBar](https://github.com/steipete/CodexBar),
baseline `8ab81e2eb` (2026-10-07), with upstream Git history and MIT license retained.

## Use

Open **CodexBar Lite.app**. It immediately reads `auth.json` in `CODEX_HOME`, or `~/.codex` if that
variable is absent. No account setup, separate login or Codex CLI executable is required.
If you use another Codex home, select it in **设置 → Codex → 认证**. macOS GUI apps may not inherit
terminal environment variables, so choosing the directory explicitly is useful for custom homes.

The original undecorated combined-style menu bar icon shows **remaining** quota. Click for 5-hour, weekly, monthly and additional
model windows supplied by the service, plus reset countdowns or clock times (Settings → General → Usage; hover a quota row for its exact reset date). Refresh manually or
every 1, 5, 15 or 30 minutes. Optional launch at login is available in Settings.
The original pace stripe and reserve/deficit/estimated-exhaustion text use upstream UsagePace
calculations from elapsed time and quota usage; no transcript scanning or stored history is needed.

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

### Upstream UI extraction (v0.3.1)

All source references below are from `8ab81e2eb`; MIT attribution is retained.

| Retained UI | Original implementation | Lite adaptation |
| --- | --- | --- |
| Status icon | `IconRenderer.swift`, Codex descriptor `visibleWindows` | Keep Codex drawing/context/face; remove other providers, credits, morph cache and service-status overlays. Adapter maps current quota windows. |
| Pace forecast | Core `UsagePace.swift`, app `UsagePaceText.swift`, `MenuCardView+ModelHelpers.swift` | Keep calculation, 3% initial-window threshold, stages and wording; specialize to Codex without history forecasts. |
| Progress and metric rows | `UsageProgressBar.swift`, `MenuCardMetricRow.swift`, `MetricRowHeader` | Original renderer and layout, with a smaller input model. |
| Settings metric rows | `ProviderMetricInlineRow`, `ProviderDetailInfoRow` | Original row layout, current account only. |
| Reset information | `MenuCardView+CodexResetCredits.swift`, `ProviderLimitResetCreditsInlineRow`, Core `CreditsModels.swift` / OAuth usage fetcher | Original inventory filtering, expiry summaries, hover details, menu/settings rows and reset-time picker; current account only, read-only supplement. |
| Refresh picker | `PreferencesMenuPicker.swift` | Original menu-backed control; supported intervals unchanged. |
| Plan and update text | `CodexPlanFormatting.swift`, `UsageFormatter.swift`, zh-Hans strings | Original formatting helpers and translations. |
| Settings shell / About | `PreferencesView.swift`, `SidebarResizeHandle.swift`, `PreferencesAboutPane.swift` | Preserve shell/materials/geometry and About styling; omit removed feature panes and updater. |

Validation: 37 offline tests pass. A scratch comparison compiled the original upstream icon renderer
with Codex-only descriptor fixtures, comparing 120 RGBA bitmap outputs against the extracted renderer
across light/dark, fresh/stale, missing/empty/partial/full quotas. All matched. The reference cache was
bypassed using a sub-visual blink value to avoid cross-appearance cache reuse. UI interaction testing
remains manual at the user's request; these comparisons do not claim every window is pixel-identical.

## Scope

Only Codex quota, resets and reset-card inventory, current-account following and basic settings. No local cost/token scanning,
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

### Installed-original style correction (v0.3.2)

The installed original is v0.55.0. Its saved settings enable mergeIcons with Codex, Gemini and
Antigravity enabled; UsageStore selects the combined visual style for multiple enabled providers.
Lite now preserves that undecorated style, while still fetching Codex only. v0.3.1 incorrectly
forced the single-provider Codex face. The raw v0.55.0 combined renderer now also passes all120
bitmap comparisons against Lite. Quota availability still determines one-meter vs two-meter layout.

### Single-quota alignment (v0.3.3)

Center the16px single meter at y=10 in the36px canvas, rather than upstream y=14.
This user-requested correction applies to one actual quota window; two-meter geometry remains
unchanged and passes80bitmap comparisons with v0.55.0. No plan-name heuristic controls lane count.
38offline tests pass, including single-meter alpha-bound vertical alignment.

### Reset information (v0.4.0)

Restore the upstream countdown/clock-time selector and limit reset credit inventory. The menu and
Codex settings show active card count and expiry summaries using upstream rows and Chinese strings;
menu hover exposes each expiry. Expired, redeemed, redeeming and unknown-status cards are excluded,
and the row is hidden when there are no active cards, matching upstream behavior.

The supplement makes one read-only GET to `/wham/rate-limit-reset-credits` with a 4-second request
timeout and the same credentials/account as the successful quota request. It never rereads login,
refreshes tokens or retries. Endpoint errors leave quota visible; a new success never retains an
older inventory. Only the latest response is kept; no notification scheduling or history storage.
Card redemption is performed in Codex, as in the upstream display-only UI. Demo mode includes a
sample card. Offline tests cover filtering, malformed/failed responses, cancellation, account
changes, card-only responses and persisted display style. UI verification remains manual.
