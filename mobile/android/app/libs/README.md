# android/app/libs

The APK links only `hysteria-client.aar`, built by `mobile/android/hysteria-bind/build-aar.sh`.

`libXray.aar` was removed. Every `libgojni.so` inside it contained
`github.com/sagernet/sing` and `github.com/sagernet/sing-shadowsocks`
(GPL-3.0-or-later, ADR 036). Do not download it and do not put it on the Gradle
classpath. `mobile/android/app/libs/*.aar` is gitignored, so a new archive in
this folder is not committed. The AARs already tracked (`hysteria-client.aar`,
`trusttunnel-client-android.aar`) stay tracked. `trusttunnel-client-android.aar`
is not on the Gradle classpath.

`hysteria-client.aar` links `apernet/hysteria` and `v2fly/v2ray-core` (MIT).
`xtls/xray-core` is not in the module graph. The license guard in
`mobile/android/hysteria-bind/license_guard_test.go` has an empty
`knownViolations` map: a copyleft module in this archive fails the build.

## The committed archive can fall behind its source

The archive in this folder is a build product, and nothing rebuilds it
automatically: no workflow runs `build-aar.sh`, and `hy2bind.go` only carries a
comment telling the reader to rebuild after changing the package. So the
committed archive and `mobile/android/hysteria-bind` can disagree — and the APK
links the archive, not the source.

That is the state as of 2026-10-09. `refactor/windows-own-engine` (#317) changed
the shared `hy2bind` package — `maybeHop`, `startFlowAPI`, `setHijackDNS`,
`setUDPDirect`, `setExtraForceSuffixes`, `bindOutsidePacket` and seven new
`startConfig` fields — and did not rebuild this archive. Measured by reading
strings and symbols out of `jni/arm64-v8a/libhyjni.so`: every one of them is
absent from the committed archive while present in the source. Positive controls
(`salamander`, `unsupported obfs`, `setDirectSuffixes`, `StartShare`) are present
in the same file, so the search is not vacuous.

**Nothing is wrong on Android today, and that was checked rather than assumed.**
Each addition is inert off Windows: `prepareOutsideDial` and `bindOutsidePacket`
are empty stubs in `hy2bind_direct_other.go`; `maybeHop` returns its input when
`server_ports` is empty; `startFlowAPI` returns when the port is 0; and
`HysteriaBridge.kt` sends only server, auth, sni, socks_listen, insecure, obfs,
obfs_password and direct_domain_suffixes — none of the new fields. The Windows
document is the only sender of those.

The hazard is the next change, not this one: an edit to the shared package made
for Android would silently not ship, and CI would stay green, because the Go
tests test the source while the Android tests link the stale archive.

The structural fix is a guard, not another rebuild — rebuild the archive in CI
and fail when it differs from the committed one, or stop committing it and build
it inside the Android job. Until one of those exists, rebuild by hand with
`build-aar.sh` after touching the package.

