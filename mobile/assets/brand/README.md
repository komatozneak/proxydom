# Brand assets — palette v3 oak+moss

## Ship (bundled)

| Path | Notes |
|---|---|
| `onboarding_globe.png` | Hero from PR #34 (oak+moss moodboard). Raster PNG. |
| `icon/` | Adaptive icon layers (fg + monochrome); bg color in flutter_launcher_icons. |
| `anim/` | Optional Rive `.riv` (connecting state) — add when ready. |
| `empty/` | Prefer code-drawn SVG / CustomPainter; keep empty for now. |

## Do not ship

`../backgrounds/textures/` and `../backgrounds/empty_states/` — see
`DEPRECATED-PR35.md` (Klein 9B non-commercial).

## Tagline

«Тёплый дом в холодном интернете»

## Rules

- No text baked into PNGs (Cyrillic = Flutter Text widgets).
- Colors only via `AppBrand.*` / `Theme.of(context).colorScheme.*`.
- No AI logo / store icon without commercial license + human review.
