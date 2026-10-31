#!/usr/bin/env bash
# Build Hy2bind.xcframework for iOS Packet Tunnel.
# Run on macOS with Go + Xcode + gomobile.
#
#   bash build-ios.sh
#
# go.mod is the only pin, as in build-aar.sh: the script never rewrites go.mod
# or go.sum, so the framework is built from the graph the commit names.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${OUT_DIR:-$ROOT/../../ios/Frameworks}"
mkdir -p "$OUT_DIR"
cd "$ROOT"

if ! go mod tidy -diff >/dev/null; then
  echo "go.mod/go.sum are not tidy: run 'go mod tidy' and commit the result" >&2
  exit 1
fi
XMOBILE_VERSION="$(go list -m -f '{{.Version}}' golang.org/x/mobile)"
echo "=== hy2bind gomobile iOS (x/mobile $XMOBILE_VERSION) ==="

if ! command -v gomobile >/dev/null 2>&1; then
  echo "Installing gomobile..."
  go install "golang.org/x/mobile/cmd/gomobile@${XMOBILE_VERSION}"
  go install "golang.org/x/mobile/cmd/gobind@${XMOBILE_VERSION}"
  export PATH="$(go env GOPATH)/bin:$PATH"
fi

# Do not bind a framework until the guard has read the graph it is built from.
# A known violation warns and the test still passes; copyleft without an entry
# stops the build.
go test -count=1 -run 'TestLicenseGuard$' .
gomobile init >/dev/null 2>&1 || true

# ios + simulator fat xcframework. Do not commit the binary.
#
# `netgo` is not a preference: iOS has no `libresolv` to resolve `res_9_ninit`,
# `res_9_nsearch` and `res_9_nclose`, which is what the cgo resolver compiles
# down to. With the default resolver the extension links and then fails at link
# time with three undefined symbols, so the pure Go resolver is selected here.
#
# -trimpath for the same reason as build-aar.sh: without it gomobile's random
# temp directory and the build machine's paths are compiled into the binary.
gomobile bind -v -trimpath -target=ios -iosversion=15.0 -tags netgo \
  -o "$OUT_DIR/Hy2bind.xcframework" .

echo "Wrote $OUT_DIR/Hy2bind.xcframework"
echo "Next: VpnTunnelProvider target already references Frameworks/Hy2bind.xcframework"
