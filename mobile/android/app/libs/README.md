# android/app/libs

The APK links only `hysteria-client.aar`, built by `mobile/android/hysteria-bind/build-aar.sh`.
That binary is both the Hysteria2 engine and the in-process Xray core (`xtls/xray-core`) used for VLESS Reality.

`libXray.aar` and `trusttunnel-client-android.aar` may sit in this folder. They are not on the Gradle classpath. Owner 2026-09-26 allows vendoring them; this slice does not link a second Xray runtime next to hy2bind.

## Not for distribution

`libXray.aar` is tracked here but must not ship. Every `libgojni.so` inside it contains
`github.com/sagernet/sing` and `github.com/sagernet/sing-shadowsocks` (GPL-3.0-or-later).
Do not put it on the Gradle classpath, copy it into an APK, AAB or release asset, or hand it to
anyone (ADR 036). It stays in the tree only until its own removal task.

`hysteria-client.aar` still carries `github.com/sagernet/sing` through `xtls/xray-core` until
`docs/ops/engine-migration/03-mobile-engine-swap.md` lands. The license guard in
`mobile/android/hysteria-bind/license_guard_test.go` reports it as a known violation.
