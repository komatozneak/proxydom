# Brand assets

## Ship (bundled)

| Path | Notes |
|---|---|
| `onboarding_globe.png` | Onboarding hero. |
| `connect/s1-flat-launcher.png` | Living House mascot (mustard + white door). Used by Home connect glyph. |
| `icon/fg_proxydom.png` | Adaptive icon foreground (from mascot). |
| `icon/mono_proxydom.png` | Android 13+ themed / monochrome silhouette. |
| `icon/nav_vpn_proxydom.png` | Bottom-nav center mark: mono house + «DOM» cutout (Latin, not l10n). |
| `rive/signal_nest_connect.riv` | Optional Rive export (Flutter painter is SoT). |

## Regenerate launcher icons

```powershell
cd mobile
python tool/generate_adaptive_icon.py
dart run flutter_launcher_icons
# Optional: re-cut DOM holes into mono for bottom nav
python tool/bake_nav_vpn_icon.py
```

Background: `#FAF8F3`. Notification / status smallIcon: `android/.../drawable/ic_stat_proxydom.xml`.

## Tagline

«Тёплый дом в холодном интернете»

## Rules

- No Cyrillic baked into PNGs (l10n = Flutter Text widgets).
- Exception: Latin «DOM» may be cut into `nav_vpn_proxydom.png` for the Ogon-style center tab.
- Colors via `AppBrand.*` / `Theme.of(context).colorScheme.*`.
- Do not resurrect `fg_oak_moss` oak+moss shield as the store icon.
