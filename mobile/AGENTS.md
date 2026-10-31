# AGENTS.md — mobile/

Rules for `mobile/`. The root `AGENTS.md` owns the names, the product, the
licence boundary, the commands and the agent workflow; this file adds only
what is specific to the Flutter app and the engine that ships inside it.

## Commands

```bash
flutter pub get
flutter analyze --no-fatal-infos
flutter test --dart-define=AUTH_ANONYMOUS=false
flutter test test/<name>_test.dart

bash android/hysteria-bind/build-aar.sh       # hysteria-client.aar (NDK, LIEF)
bash android/hysteria-bind/build-ios.sh       # Hy2bind.xcframework (macOS)
cd android && ./gradlew :app:testDebugUnitTest  # needs the AAR above
pwsh android/build-sideload.ps1               # local sideload APK
```

## Layout

```
lib/core/                 theme, config, shared widgets, diagnostics
lib/features/<feature>/   data/ · application/ · presentation/
lib/l10n/                 ARB sources; app_localizations*.dart are generated
android/app/              Kotlin VpnService, MethodChannel `proxydom/vpn`
android/hysteria-bind/    Go engine for Android, iOS and Windows
ios/Runner, ios/VpnTunnelProvider   Flutter host and Packet Tunnel
```

## What may start

`lib/features/vpn/data/dial_set.dart` is the only authority for which line
starts on which platform, and `engine_share_config.dart` for what the engine can
describe. Do not restate that set anywhere else. A line this platform cannot
start stays in its document with a neutral badge: it is counted, named and never
deleted.

## Build products

`hysteria-client.aar` and `Hy2bind.xcframework` are not in git and are not
source: the Go package is. Both scripts build from the graph `go.mod` names and
refuse an untidy one rather than rewriting it. CI builds the AAR once in the
`hy2bind-aar` job and passes it to the Android jobs as an artifact (building it
inside a consumer runs the four-ABI APK out of disk). `build-sideload.ps1`
refuses a production APK whose archive predates `hysteria-bind`. Details:
`android/app/libs/README.md`.

## Android

`minSdk = 26` is enforced by `requiredMinSdk` in `android/app/build.gradle.kts`
(through `finalizeDsl`, because Flutter rewrites a literal `minSdk`). Do not
lower it: hy2bind and `VpnService` need it.

## Brand and UI

- Tokens live only in `lib/core/theme.dart` (`AppBrand.*`); themes are
  `AppTheme.light` / `AppTheme.dark`, Material 3, fixed (no Material You).
  Rationale: `docs/design/palette-v3-decision.md`.
- No `Color(0xFF…)` or `Colors.*` in widgets — `Theme.of(context).colorScheme`
  or `AppBrand`. The honey accent `#FF8F00` is intentional; error is oak brown.
- UI strings come from `lib/l10n/` ARB files, never inline.
- Icons: Phosphor through `lib/core/widgets/app_icon.dart`, static constants
  only (never `IconData(0x…)`, which breaks icon tree-shaking).
- Launcher icons: `dart run flutter_launcher_icons`. The Windows `.ico` is baked
  by `tool/bake_windows_icon.py`, never hand-edited, and the exe must be rebuilt
  after a rebake (the MSI takes its icon from `proxy_dom.exe`).
- No AI-generated images without a commercial licence for them.

## Tests

Test behaviour through public APIs and widgets. Brand changes get widget or
asset tests (`palette_v3_test.dart`, `hero_asset_test.dart`,
`phosphor_swap_test.dart`); do not rewrite unrelated smoke coverage.
