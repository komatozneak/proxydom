# android/app/libs

The APK links only `hysteria-client.aar`, built by `mobile/android/hysteria-bind/build-aar.sh`.

`libXray.aar` was removed. Every `libgojni.so` inside it contained
`github.com/sagernet/sing` and `github.com/sagernet/sing-shadowsocks`
(GPL-3.0-or-later, ADR 036). Do not download it and do not put it on the Gradle
classpath. `mobile/android/app/libs/*.aar` is gitignored. The one AAR still
tracked, `trusttunnel-client-android.aar`, is not on the Gradle classpath.

`hysteria-client.aar` links `apernet/hysteria` and `v2fly/v2ray-core` (MIT).
`xtls/xray-core` is not in the module graph. The license guard in
`mobile/android/hysteria-bind/license_guard_test.go` has an empty
`knownViolations` map: a copyleft module in this archive fails the build.

## The archive is a build product, not a committed artifact

`hysteria-client.aar` is not in git. `build-aar.sh` produces it,
`mobile/android/build-sideload.ps1` requires it on disk for a production APK, and
iOS has always worked this way: `Hy2bind.xcframework` is built by `build-ios.sh`
and is not committed either.

In CI the Android jobs take it as an artifact rather than each building it. A
`hy2bind-aar` job runs the composite action
`.github/actions/build-hy2bind-aar`, uploads the archive and its `.source-hash`
sidecar, and the jobs that link the archive download it. Building the archive
inside each consumer looks simpler and is wrong: the bind pulls the Go module
cache, the Go build cache and four ABIs onto the same machine that then has to
package a four-ABI APK. Measured on a dispatch of `android-apk.yml` with the bind
inline, the bind succeeded and `:device_info_plus:compileReleaseKotlin` then died
with `No space left on device`.

This replaces committing the archive, which cost a 57 MB blob per rebuild — 12
versions and 573.8 MB across history — and left a trap: #317 changed the shared
`hy2bind` package without rebuilding, so the archive was nine commits behind its
source, and CI stayed green because the Go tests test the source while the
Android tests linked the stale archive.

Gradle now fails with the command to run when the archive is absent, instead of
silently dropping the dependency and surfacing much later as an unresolved
reference to `hy2bind.Hy2bind` from `HysteriaBridge.kt`.

## A stale archive still ships the old engine

Building the archive in CI fixes CI, but not a laptop: `build-sideload.ps1`
builds a production APK from whatever archive happens to be in this folder. Edit
`hy2bind` and run that script without rerunning `build-aar.sh`, and the APK
carries the previous engine with nothing to show for it.

`build-aar.sh` therefore writes `hysteria-client.aar.source-hash` — a hash of
the package source it just built — beside the archive, and
`build-sideload.ps1` refuses to build when the two disagree. `aar_stamp_test.go`
runs the same check during `go test ./...`, and skips on a fresh checkout where
there is no archive to compare.

The hash is over the archive's inputs, not the archive's bytes: a byte
comparison would need the exact toolchain of whoever built the file, and
`actions/setup-go` on CI pins a different Go than `go.mod` asks for. This is the
same shape as `Get-DartSourceStamp` in
`desktop/windows/installer/build-msi.ps1`, which refuses to package a Flutter
snapshot that no longer matches `mobile/lib`.

`build-aar.sh` passes `-trimpath`, and that is load-bearing rather than
cosmetic: gomobile builds in a randomly named temporary directory and compiles
that path into the libraries. Measured on one machine, two binds of the same
source without `-trimpath` produced arm64 libraries of 31 033 792 and
31 033 832 bytes with different hashes; with it, two binds produced one
identical 30 957 992-byte library. It also keeps the build machine's absolute
paths, and the user name inside them, out of the shipped APK.
