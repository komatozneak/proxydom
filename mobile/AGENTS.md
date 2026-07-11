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

Do **not** hardcode `Color(0xFF…)` or `Colors.teal` / `Colors.red` in widgets —
use `Theme.of(context).colorScheme.*` or `AppBrand.*`.

## Stack

- Flutter + Riverpod + go_router + Dio
- VPN core: sing-box (native), MethodChannel `teremok/vpn`
- minSdk **23** (hard requirement — do not roll back)

## Tests

Add new tests for palette / brand changes; prefer not rewriting unrelated smoke
coverage. Palette suite: `test/palette_v3_test.dart`, `test/hero_asset_test.dart`,
`test/palette_consistency_test.dart`.
