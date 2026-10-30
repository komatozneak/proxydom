#!/usr/bin/env bash
# Build official apernet/hysteria into hysteria-client.aar (gomobile).
# Not sing-box. Not Bereznev-HY2-Core.
#
# Requires: Go 1.23+, Android NDK (ANDROID_NDK_HOME), javac, python3, and the
# `lief` Python package (namespace_aar.py rebuilds the ELF GNU hash with it, and
# a raw byte rename leaves hy.Seq.init() dying with UnsatisfiedLinkError).
# gomobile and gobind are installed here if missing, as in build-ios.sh.
# The output is written to ../app/libs/hysteria-client.aar, which is gitignored:
# the archive is a build product, not a committed artifact.
#
# CI installs lief in .github/actions/build-hy2bind-aar before calling this.
#
# Usage (from this directory):
#   HYSTERIA_TAG=v2.13.0 bash build-aar.sh
#
# v2.13.0 is the hysteria release that compiles against the quic-go module
# version selected by v2ray-core v5.54.2. An older pin fails the build.
set -euo pipefail

HYSTERIA_TAG="${HYSTERIA_TAG:-v2.13.0}"
OUT_DIR="$(cd "$(dirname "$0")/../app/libs" && pwd)"
OUT_AAR="$OUT_DIR/hysteria-client.aar"

echo "=== hy2bind gomobile (hysteria $HYSTERIA_TAG) ==="
cd "$(dirname "$0")"

# Mirror build-ios.sh: the script is self-sufficient, so CI runs the same
# command a developer runs and there is no second, drifting recipe.
if ! command -v gomobile >/dev/null 2>&1; then
  echo "Installing gomobile..."
  go install golang.org/x/mobile/cmd/gomobile@latest
  go install golang.org/x/mobile/cmd/gobind@latest
  export PATH="$(go env GOPATH)/bin:$PATH"
fi
# Harmless when already initialised, as build-ios.sh does it.
gomobile init >/dev/null 2>&1 || true

go get "github.com/apernet/hysteria/core/v2@${HYSTERIA_TAG}"
# Go 1.25+: gomobile bind needs x/mobile in this module's tool graph.
# Pin the tool to the version go.mod already selects. `go get -tool ...@latest`
# rewrote eight x/* modules in go.mod and go.sum on every bind, so the archive
# that shipped was built from a dependency graph the commit did not name — and
# two machines binding the same commit could disagree. aarstamp hashes go.mod
# and go.sum, so that drift also invalidated every sidecar written elsewhere.
GOBIND_VERSION="$(go list -m -f '{{.Version}}' golang.org/x/mobile)"
go get -tool "golang.org/x/mobile/cmd/gobind@${GOBIND_VERSION}"
go mod tidy
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# tidy can pull a module the committed go.mod did not have.: do not
# bind an archive until the guard has read that graph. build-ios.sh has always
# done this and this script did not, which was tolerable while the archive was
# built by hand and became a real hole once CI started producing it.
# A known violation warns and the test still passes; copyleft without an entry
# stops the build.
go test -count=1 -run 'TestLicenseGuard$' .

# Stamp the source AFTER binding, so the sidecar records what was just built.
# build-sideload.ps1 verifies it before building a production APK: Gradle links
# this archive and not the Go source, so a stale archive ships the old engine
# silently.

# -trimpath is not cosmetic here: gomobile builds in a randomly named temporary
# directory, and without this flag that path is compiled into the libraries.
# Measured: two binds of the same source without -trimpath produced arm64
# libraries of 31033792 and 31033832 bytes with different hashes, and with it
# two binds produced one identical 30957992-byte library. It also keeps the
# build machine's absolute paths, and the user name in them, out of the APK.
gomobile bind -v -trimpath -target=android -androidapi=26 -o "$OUT_AAR" .
# Relocate go.Seq and libgojni.so. A second gomobile archive on the classpath
# (the removed libXray.aar) collided on those names, and AGP still rejects
# the stock names via checkDebugDuplicateClasses.
if command -v python3 >/dev/null 2>&1; then
  python3 "$SCRIPT_DIR/namespace_aar.py" "$OUT_AAR"
else
  python "$SCRIPT_DIR/namespace_aar.py" "$OUT_AAR"
fi
echo "=== aar stamp ==="
go run ./cmd/aarstamp stamp "$SCRIPT_DIR" "$OUT_AAR"
echo "Wrote $OUT_AAR"
ls -la "$OUT_AAR" "$OUT_AAR.source-hash"
