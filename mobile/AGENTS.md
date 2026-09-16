# Mobile AGENTS — Teremok Connect client

Rules for AI agents working in `mobile/`. Complements root `AGENTS.md`.

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
- Adaptive icon: `assets/icon/fg_oak_moss.png` + `mono.png` + cream bg
  (`flutter_launcher_icons`; regenerate with `dart run flutter_launcher_icons`)
- Motion: CustomPainter / progress indicators for now; **rive deferred** (SDK)

### PR #35 assets — DO NOT SHIP

`assets/backgrounds/textures/` and `empty_states/` are **deprecated** (FLUX Klein
9B non-commercial). See `assets/brand/DEPRECATED-PR35.md`. Not in `pubspec.yaml`.

Do **not** hardcode `Color(0xFF…)` or `Colors.teal` / `Colors.red` in widgets —
use `Theme.of(context).colorScheme.*` or `AppBrand.*`.

Do **not** bulk-generate AI PNGs without commercial license + owner go (Visual A→B).

## Stack

- Flutter + Riverpod + go_router + Dio
- VPN core: Hysteria2 / hy2bind (ADR 018), MethodChannel `teremok/vpn`
- minSdk **26** (hard requirement — do not roll back)
- Billing: **Platega hosted only on Android** (ADR 017). Do **not** add Play Billing /
  `com.android.vending.BILLING`. On **iOS**, hide Platega CTA (`hideInAppPlategaCheckout`);
  see ADR 019 + `docs/ops/ios-iap-parked.md`.

## Tests

Add new tests for palette / brand changes; prefer not rewriting unrelated smoke
coverage. Palette suite: `test/palette_v3_test.dart`, `test/hero_asset_test.dart`,
`test/palette_consistency_test.dart`, `test/phosphor_swap_test.dart`.
