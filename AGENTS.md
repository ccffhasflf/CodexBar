# CodexBar Lite

A macOS 14+ Codex-only menu bar app. Follow the current native Codex auth.json automatically;
keep quota windows, reset times, manual/timed refresh and login-at-startup.
Account backup/restore is deferred: future switching will replace auth.json and the user will restart Codex manually. Do not reintroduce cost scans, transcripts,
WebKit, other providers, plugins, widgets or a standalone CLI without a scope change.

Preserve upstream CodexBar menu and settings UI; simplify functionality, not the visual design.

## Structure
- `Sources/CodexBarLiteCore`: quota parsing, HTTP, native credential files, accounts and refresh state.
- `Sources/CodexBarLite`: SwiftUI menu/settings and app lifecycle.
- `Tests/CodexBarLiteTests`: offline fixtures, current-auth monitoring and in-flight account-change tests.
- `Scripts/package_app.sh`: local ad-hoc signed bundle; does not install or replace any app.

## Validation
- Run `make check` and `make test` after relevant code changes. `make format` formats Swift.
- Build a release bundle with `make package`. Use `--demo` for UI/runtime validation.
- Never run live credential probes, browser-cookie imports, Keychain reads or live login during tests
  unless explicitly requested. All tests use temporary homes and injected transports.
- Use Swift 6, explicit self, 4 spaces and 120-character lines. Preserve MIT attribution.
- Keep the current Codex home read-only. Do not back up or replace auth.json in this version.
  Old managed-account data remains preserved but is not used by the app.
- Coalesce refresh requests, cancel/drain before account removal, and retain only the latest snapshot per account.
- Do not add third-party dependencies without discussion. Preserve the upstream Git history.
