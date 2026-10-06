# Mobile AGENTS — Прокси Дом

Rules for AI agents working in `mobile/`. Complements root `AGENTS.md`.

## Name

Google Play: **Прокси Дом**. English name: **Proxy Dom**. Package **`com.proxy.dom`**. The Telegram bot stays **Теремок VPN**.
Repo stays `teremok` / `teremokconnect`. Dart package is **`proxydom`**. Android `applicationId` is `com.proxy.dom`; Kotlin `namespace` is `com.proxydom.app`.
iOS bundle id is **`su.proxydom.app`** (extension `su.proxydom.app.VpnTunnelProvider`, App Group
`group.su.proxydom.app`). The VPN profile name is **Прокси Дом**. The former `online.teremokconnect.app` belonged to the abandoned project.
Name rule: `.cursor/rules/05-product-names.mdc`.

`test/free_client_copy_test.dart` fails the build if selling copy or the old brand appears under `lib/`, `ios/`, or `android/`. Parser data (`· Premium`), the legacy `teremok://` import scheme, shade-channel ids kept only so old tester installs can delete them, and the upload keystore filename are allowlisted in that test with a reason.

## Dial set

**Hysteria2 only** — `hy2://` and `hysteria2://`, including `obfs=salamander` and port hop — on Android, iOS, and Windows. VLESS and VLESS Reality dial is **parked** on every platform (ADR 033): the parser still reads `vless://`, the dial gate does not admit it. Trojan, Shadowsocks, and VMess are out of the product. Engines: hy2bind is the one that runs. `libXray.aar` was removed because it embeds `sagernet/sing` (GPL-3.0, ADR 036); do not fetch it back. `libbox` is sing-box and must not be vendored. hev stays dormant — do not call it from the active connect path. Policy: `docs/product-policy.md`. Authority: `docs/decisions/033-client-hy2-only-dial-set.md`.

## Brand / palette

**Current:** palette **v3 «Дуб и мох»** (2026-07-11).

- Tokens live only in `lib/core/theme.dart` → `AppBrand.*`
- Themes: `AppTheme.light` / `AppTheme.dark` (Material 3, fixed — no Material You)
- Accent honey `#FF8F00` is intentional and must stay
- Error is oak brown (not Material red) — anti-pattern fix
- Docs: `docs/design/palette-v3-decision.md`
- Hero: `assets/brand/onboarding_globe.png` (raster PNG from oak+moss moodboard)
- Icons: **Phosphor** via `lib/core/widgets/app_icon.dart` (`AppIcons.*` /
  `PhosphorIconsRegular.*` static only — never dynamic `IconData(0x…)`)
- Adaptive icon: `assets/icon/fg_proxydom.png` + `mono_proxydom.png` + cream bg
  (`flutter_launcher_icons`; regenerate with `dart run flutter_launcher_icons`)
- Windows icon: `windows/runner/resources/app_icon.ico` — **bake it, never hand-edit**.
  `tool/bake_windows_icon.py` cuts it from `assets/icon/nav_vpn_proxydom.png` (the DOM
  mark) at 16–256 px with transparent corners; `tool/bake_web_icon.py` bakes the same
  mark for the landing. After a rebake the exe must be rebuilt — the MSI pulls its
  icon from `proxy_dom.exe`, not from the `.ico`.
- Motion: CustomPainter / progress indicators for now; **rive deferred** (SDK)

### PR #35 assets — DO NOT SHIP

`assets/backgrounds/textures/` and `empty_states/` are **deprecated** (FLUX Klein
9B non-commercial). See `assets/brand/DEPRECATED-PR35.md`. Not in `pubspec.yaml`.

Do **not** hardcode `Color(0xFF…)` or `Colors.teal` / `Colors.red` in widgets —
use `Theme.of(context).colorScheme.*` or `AppBrand.*`.

Do **not** bulk-generate AI PNGs without commercial license + owner go (Visual A→B).

## Stack

- Flutter + Riverpod + go_router + Dio
- VPN core: Hysteria2 / hy2bind (ADR 018), MethodChannel `proxydom/vpn`
- minSdk **26** (hard requirement — do not roll back)
- Billing: **Platega hosted on Android** (ADR 017); Play Billing не используется.
  **iOS-сборка — чистая утилита, оплаты нет вообще**: ни Platega, ни каталога,
  ни Premium/квот/бота-кассира. Требование App Review Guideline 5.4, обоснование —
  `docs/ops/apple-org-umicum-runbook.md` §5.2. Флаг `hideInAppPlategaCheckout`
  больше не основной механизм — код оплаты в iOS-сборке отсутствует.

## Tests

Add new tests for palette / brand changes; prefer not rewriting unrelated smoke
coverage. Palette suite: `test/palette_v3_test.dart`, `test/hero_asset_test.dart`,
`test/palette_consistency_test.dart`, `test/phosphor_swap_test.dart`.
