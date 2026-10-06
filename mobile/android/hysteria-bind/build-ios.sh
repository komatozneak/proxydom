#!/usr/bin/env bash
# Build Hy2bind.xcframework for iOS Packet Tunnel (ADR 019).
# Run on macOS with Go + Xcode + gomobile. Pin matches Android build-aar.sh.
#
#   HYSTERIA_TAG=v2.13.0 bash build-ios.sh
#
# v2.13.0 matches build-aar.sh: older hysteria does not compile against the
# quic-go module v2ray-core v5.54.2 selects.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
HYSTERIA_TAG="${HYSTERIA_TAG:-v2.13.0}"
OUT_DIR="${OUT_DIR:-$ROOT/../../ios/Frameworks}"
mkdir -p "$OUT_DIR"

echo "=== hy2bind gomobile iOS (hysteria $HYSTERIA_TAG) ==="
cd "$ROOT"

if ! command -v gomobile >/dev/null 2>&1; then
  echo "Installing gomobile..."
  go install golang.org/x/mobile/cmd/gomobile@latest
  go install golang.org/x/mobile/cmd/gobind@latest
  export PATH="$(go env GOPATH)/bin:$PATH"
fi

go get "github.com/apernet/hysteria/core/v2@${HYSTERIA_TAG}"
go get -tool golang.org/x/mobile/cmd/gobind
go mod tidy
# tidy can pull a module the committed go.mod did not have. ADR 036: do not
# bind an xcframework until the guard has read that graph. A known violation
# warns and the test still passes; copyleft without an entry stops the build.
go test -count=1 -run 'TestLicenseGuard$' .
gomobile init >/dev/null 2>&1 || true

# ios + simulator fat xcframework. Do not commit the binary.
gomobile bind -v -target=ios -iosversion=13.0 \
  -o "$OUT_DIR/Hy2bind.xcframework" .

echo "Wrote $OUT_DIR/Hy2bind.xcframework"
echo "Next: VpnTunnelProvider target already references Frameworks/Hy2bind.xcframework"
