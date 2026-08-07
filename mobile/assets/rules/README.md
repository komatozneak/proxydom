# Local sing-box rule-sets (RF-safe)

Ship binary `.srs` files in the APK. **Never** fetch from GitHub/jsDelivr at
connect time — RF blocks that path (2026-07-14).

## Files

| Tag | File | Role |
|-----|------|------|
| `geosite-category-ru` | `geosite-category-ru.srs` | Smart mode → direct |
| `geosite-tld-ru` | `geosite-tld-ru.srs` | Smart mode → direct |
| `geoip-ru` | `geoip-ru.srs` | Shipped; runtime OFF (`kGeoipRuEnabled`) — CDN false positives |
| `geosite-category-ads-all` | `geosite-category-ads-all.srs` | Ad block → reject; runtime OFF (`kAdsBlockEnabled`) |

Policy constants: `mobile/lib/features/vpn/data/vpn_route_policy.dart`.
Constructor: `VpnConfigConstructor` in `vpn_config_constructor.dart`.

## Refresh ads list (offline / CI with network)

```bash
curl -fsSL -o mobile/assets/rules/geosite-category-ads-all.srs \
  "https://cdn.jsdelivr.net/gh/SagerNet/sing-geosite@rule-set/geosite-category-ads-all.srs"
```

Commit the binary. Bump APK. No runtime update.
