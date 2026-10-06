# android/app/libs

The APK links only `hysteria-client.aar`, built by `mobile/android/hysteria-bind/build-aar.sh`.

`libXray.aar` was removed. Every `libgojni.so` inside it contained
`github.com/sagernet/sing` and `github.com/sagernet/sing-shadowsocks`
(GPL-3.0-or-later, ADR 036). Do not download it and do not put it on the Gradle
classpath. `mobile/android/app/libs/*.aar` is gitignored, so a new archive in
this folder is not committed. The AARs already tracked (`hysteria-client.aar`,
`trusttunnel-client-android.aar`) stay tracked. `trusttunnel-client-android.aar`
is not on the Gradle classpath.

`hysteria-client.aar` still carries `github.com/sagernet/sing` through
`xtls/xray-core` until `docs/ops/engine-migration/03-mobile-engine-swap.md`
lands. The license guard in `mobile/android/hysteria-bind/license_guard_test.go`
reports it as a known violation.
