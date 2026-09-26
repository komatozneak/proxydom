# android/app/libs

The APK links only `hysteria-client.aar`, built by `mobile/android/hysteria-bind/build-aar.sh`.
That binary is both the Hysteria2 engine and the in-process Xray core (`xtls/xray-core`) used for VLESS Reality.

`libXray.aar` and `trusttunnel-client-android.aar` may sit in this folder. They are not on the Gradle classpath. Owner 2026-09-26 allows vendoring them; this slice does not link a second Xray runtime next to hy2bind.
