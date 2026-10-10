# Contributing

Issues and pull requests are welcome. This file is short on purpose; the
reasoning behind most rules lives in [`AGENTS.md`](AGENTS.md).

## Before you start

Open an issue first for anything larger than a bug fix. The client has a
deliberately narrow scope — it is a local configuration tool, not a service —
and a change that widens it will be declined however well it is built.

## What the client must not become

These are product boundaries, not preferences:

- **No accounts, no payments, no catalog.** The app reads a key or a document
  the user already has. It does not sell access, issue subscriptions, or phone
  home with credentials.
- **No copyleft dependencies.** MIT, BSD, ISC, Apache-2.0 and MPL-2.0 only.
  GPL-3.0 and AGPL-3.0 are incompatible with the App Store terms, so a copyleft
  dependency breaks the iOS build even though the app is free.
- **No `libbox`, no `sing-box`, no `xray-core`.** All three drag in GPL-3.0.
  The engine is `hy2bind` over `v2fly/v2ray-core` (MIT).
- **No billing library.** `com.android.vending.BILLING` stays out of the
  manifest.
- **No backend.** There is no FastAPI service, bot, or node catalog in this
  repository; do not add one.

## Building

Android, iOS and Windows share the Flutter application in `mobile/`. The Go
engine in `mobile/android/hysteria-bind/` is compiled into a gomobile archive
for Android, an XCFramework for iOS, and `proxydom-engine.exe` for Windows.

```bash
# Flutter client
cd mobile
flutter pub get
flutter analyze --no-fatal-infos
flutter test --dart-define=AUTH_ANONYMOUS=false

# Go engine
cd mobile/android/hysteria-bind
go test ./...
```

The Android build needs the gomobile archive, which is a build product and is
**not** committed. CI builds it in the `hy2bind-aar` job and passes it to the
jobs that link it. To build it locally:

```bash
cd mobile/android/hysteria-bind
bash build-aar.sh
```

That script needs Go, a JDK, and `lief==1.0.0`:

```bash
python -m pip install lief==1.0.0
```

Do not commit the archive or its `-sources.jar`. `.gitignore` already excludes
them; if you find yourself editing it to add one back, that is the wrong fix.

## Tests

Run the suite that matches what you touched before opening a pull request. CI
runs the same commands, so a green local run means a green CI run.

| Touched | Run |
|---|---|
| `mobile/lib/`, `mobile/test/` | `flutter analyze --no-fatal-infos` and `flutter test` |
| `mobile/android/` | `flutter test`, plus the Android unit tests (CI job `android-unit-test`) |
| `mobile/android/hysteria-bind/` | `go test ./...` |
| `mobile/ios/` | the iOS TestFlight workflow, dispatched manually |
| `desktop/windows/` | the Windows Service workflow |

A test proves behaviour, not a checkbox. A test that would pass against a broken
implementation is worth less than no test, because it claims coverage it does
not have.

Do not add a test that asserts on internals you are about to change; assert on
what the user gets.

## Commits and pull requests

[Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`,
`docs:`, `refactor:`, `chore:`, `build:`, `test:`.

One commit is one revertable behaviour, and the tree builds at every commit.
Commit messages, code comments and PR text are English. User-facing text is
localised through `mobile/lib/l10n/`; do not hardcode Russian or English strings
in widgets.

In the pull request, say what you verified and how. "Should work" is not a test
result. If you could not verify something — a physical device, a live tunnel —
say so plainly rather than implying it was checked.

## Developer Certificate of Origin

By contributing you certify that you wrote the contribution, or that it is
derived from a source under a compatible permissive licence, and that you have
the right to submit it under the MIT licence of this repository.

## Reporting a security problem

Do not open a public issue. See [`SECURITY.md`](SECURITY.md).
