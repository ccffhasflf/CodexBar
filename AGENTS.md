# CodexBar Lite

A macOS 14+ Codex-only menu bar app. Keep quota windows, reset times, multiple accounts,
manual/timed refresh and login-at-startup. Do not reintroduce cost scans, transcripts,
WebKit, other providers, plugins, widgets or a standalone CLI without a scope change.

## Structure
- `Sources/CodexBarLiteCore`: quota parsing, HTTP, native credential files, accounts and refresh state.
- `Sources/CodexBarLite`: SwiftUI menu/settings, app lifecycle and Codex CLI browser login.
- `Tests/CodexBarLiteTests`: offline fixtures, including fake login executables.
- `Scripts/package_app.sh`: local ad-hoc signed bundle; does not install or replace any app.

## Validation
- Run `make check` and `make test` after relevant code changes. `make format` formats Swift.
- Build a release bundle with `make package`. Use `--demo` for UI/runtime validation.
- Never run live credential probes, browser-cookie imports, Keychain reads or live login during tests
  unless explicitly requested. All tests use temporary homes and injected transports.
- Use Swift 6, explicit self, 4 spaces and 120-character lines. Preserve MIT attribution.
- Keep linked Codex homes read-only. Token rotation and account deletion apply only to Lite-owned homes.
- Coalesce refresh requests, cancel/drain before account removal, and retain only the latest snapshot per account.
- Do not add third-party dependencies without discussion. Preserve the upstream Git history.
