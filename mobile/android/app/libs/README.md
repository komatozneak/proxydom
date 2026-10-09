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

## The committed archive is tied to its source by a stamp

The archive in this folder is a build product, and no workflow rebuilds it. So
the committed archive and `mobile/android/hysteria-bind` could disagree — and
the APK links the archive, not the source. That happened: #317 changed the
shared package and did not rebuild, and CI stayed green because the Go tests
test the source while the Android tests link the stale archive.

That is now enforced rather than trusted. `build-aar.sh` writes
`mobile/android/hysteria-bind/aar_stamp.go` — a hash of the package source —
before it binds, so the archive carries the hash of what it was built from.
`aar_stamp_test.go` then checks both halves:

- the stamp in the tree matches the package source;
- the stamp is present inside `jni/arm64-v8a/libhyjni.so` of the committed
  archive.

Editing the stamp by hand passes the second check and fails the first.
Rewriting it without rebuilding passes the first and fails the second. Only
`build-aar.sh`, which stamps and then binds, passes both. Both checks run in the
existing `hy2bind Go tests` job, which needs no NDK and takes seconds.

`build-aar.sh` also passes `-trimpath`, and that is load-bearing rather than
cosmetic: gomobile builds in a randomly named temporary directory and compiles
that path into the libraries. Measured on one machine, two binds of the same
source without `-trimpath` produced arm64 libraries of 31 033 792 and
31 033 832 bytes with different hashes; with it, two binds produced one
identical 30 957 992-byte library. It also keeps the build machine's absolute
paths, and the user name inside them, out of the shipped APK.

