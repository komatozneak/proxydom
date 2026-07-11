# Palette v3 decision — «Дуб и мох» (2026-07-11)

## Source of truth

Wiki (Hermes): `wiki/raw/papers/teremok-palette-v3-decision-2026-07-11.md`

> At epic start this file was not yet pushed to the `teremok-wiki-` submodule.
> This mobile doc mirrors the user-locked decision from Cursor Brief v6 so the
> app tree stays self-contained until Hermes completes the wiki sweep.

Related research (expected wiki paths):

- `wiki/raw/papers/palettes-oak-moss-peach-cream-research-2026-07-11.md`
- `wiki/raw/papers/flux-klein-prompt-patterns-2026-07-11.md`

Moodboard source (local): `Desktop/moodboard/v3_oak_moss/oak_moss_hero_01.png`
→ shipped as `mobile/assets/brand/onboarding_globe.png`.

## Why oak+moss

User compared 80 PNG raffles (40 hero + 10 wireframes per palette). MOA scored
oak+moss **40/50** vs peach **26/50**.

1. Semantics match «Теремок» (wooden house in a forest).
2. Hero is self-contained (continents = wood, arcs = amber, connected = moss glow).
3. Trust metaphor: «крепок как дуб», тайга / мох.
4. Cultural native (Russian forest, not Mediterranean).
5. Migration-friendly: teal `#00897B` evolves into moss, not a hard reset.

Tagline: **«Тёплый дом в холодном интернете»**.

## HEX tokens (AppBrand)

| Token | HEX | Role |
|-------|-----|------|
| `primary` | `#5D4037` | Oak — AppBar, primary CTA |
| `primaryContainer` | `#8D6E63` | Oak light — M3 containers |
| `secondary` | `#558B2F` | Moss — progress / secondary |
| `accent` | `#FF8F00` | Honey — brand highlight (unchanged) |
| `success` | `#2E7D32` | Sage — connected |
| `error` | `#5D4037` | Oak — soft error (NOT red) |
| `warning` | `#FF8F00` | Honey — connecting |
| `surfaceLight` | `#FAF8F3` | Cream parchment |
| `surfaceDark` | `#3E2723` | Oak dark |
| `surfaceVariantDark` | `#4E342E` | Mid oak cards |
| `info` | `#33691E` | Forest — info chips (new) |

Implementation: `mobile/lib/core/theme.dart` (`AppBrand` + `AppTheme.light/dark`).
`AppBrand.info` is also wired to `ColorScheme.inversePrimary`.

## Migration map v1 → v3

| Token | v1 (teal) | v3 (oak+moss) |
|-------|-----------|---------------|
| Primary | `#00897B` teal | `#5D4037` oak |
| Primary container | *(derived)* | `#8D6E63` oak light |
| Secondary | *(derived slate)* | `#558B2F` moss |
| Accent | `#FF8F00` | `#FF8F00` (same) |
| Surface light | `#F5F5F5` | `#FAF8F3` cream |
| Surface dark | `#121212` | `#3E2723` oak dark |
| Success | `#43A047` | `#2E7D32` sage |
| Error | `#E53935` red | `#5D4037` oak |
| Warning | `#FFA000` | `#FF8F00` |
| Info | — | `#33691E` forest |

## Anti-lumberjack notes

Borrowed from the peach runner-up so the UI stays approachable:

1. **Soft saturation** — moss stays muted sage (`#558B2F`), never emerald
   `#00C853`. Oak stays light with grain feel, not mahogany.
2. **Approachability** — cream parchment (`#FAF8F3`) + oak light containers as
   secondary surfaces; avoid rugged / cabin-core contrast.
3. If dark UI feels too heavy, prefer `surfaceVariantDark` `#4E342E` over pushing
   `surfaceDark` darker.
4. WCAG AA: cream `#FAF8F3` on oak `#5D4037` ≈ 7.5:1 — pass. Keep body text on
   cream / oak pairs; do not place low-contrast moss-on-cream for long copy.

## Negative scope (this epic)

- No `google_fonts` / `flutter_svg` / `lottie`.
- No Material You dynamic color.
- No SVG hero — raster `Image.asset('assets/brand/onboarding_globe.png')`.
- Hex literals only inside `AppBrand`; screens use `colorScheme` / `AppBrand`.

## Screenshots

Placeholder gallery: `mobile/docs/screenshots/v3/` (Pixel captures post-merge).
