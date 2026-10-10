# Android geodata assets

| File | Size | Contents | Provenance |
|------|------|----------|------------|
| `geosite.dat` | 16.6 MB | domain categories | loyalsoldier / v2fly |
| `geoip.dat` | 10.1 MB | IP lists | loyalsoldier / v2fly |

Both are in the `v2fly` geodata format.

## Nothing reads these today

They are left over from the Xray era. The current engine is `hy2bind` —
`v2fly/v2ray-core` v5.54.2 (MIT) plus `apernet/hysteria` — built by
`mobile/android/hysteria-bind/build-aar.sh`.

Its loader, `hy2bind_engine_load.go`, builds routing rules from `ip` CIDR
literals only: `shareRules` reads `ip` and `outboundTag`, and emits
`routercommon.GeoIP{Cidr: …}`. It sets no `domain` field, no country-code
`GeoIP`, and configures no geodata loader, so a `geosite:` or `geoip:` tag
cannot be resolved by it.

No Dart or Kotlin code opens these files either. There is no `getAssets`, no
`AssetManager` and no `datDir` anywhere in the tree, and `pubspec.yaml` does not
declare them. Android packages everything under `src/main/assets/` regardless,
so they still add 26.6 MB to every APK.

The tags the removed Xray builder used to emit — `geosite:category-ru`,
`geosite:tld-ru`, `geosite:category-gov-ru`, `geosite:category-ads-all`,
`geoip:ru` — therefore have no consumer.

## Do not reintroduce libXray

`libXray.aar` and its `XrayBridge` were removed with the engine swap. Every
`libgojni.so` inside that archive contained `github.com/sagernet/sing` and
`github.com/sagernet/sing-shadowsocks` (GPL-3.0-or-later), which cannot ship —
see `AGENTS.md` §6. The pin and the asset-copy routine described by earlier
revisions of this file no longer exist.
