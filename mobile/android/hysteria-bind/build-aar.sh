#!/usr/bin/env bash
# Build official apernet/hysteria into hysteria-client.aar (gomobile).
# Not sing-box. Not Bereznev-HY2-Core.
#
# Requires: Go 1.23+, Android NDK, javac, gomobile.
#   go install golang.org/x/mobile/cmd/gomobile@latest
#   go install golang.org/x/mobile/cmd/gobind@latest
#   gomobile init
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
go get "github.com/apernet/hysteria/core/v2@${HYSTERIA_TAG}"
# Go 1.25+: gomobile bind needs x/mobile in this module's tool graph.
go get -tool golang.org/x/mobile/cmd/gobind
go mod tidy
gomobile bind -v -target=android -androidapi=26 -o "$OUT_AAR" .
# Relocate go.Seq and libgojni.so. A second gomobile archive on the classpath
# (the removed libXray.aar) collided on those names, and AGP still rejects
# the stock names via checkDebugDuplicateClasses.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if command -v python3 >/dev/null 2>&1; then
  python3 "$SCRIPT_DIR/namespace_aar.py" "$OUT_AAR"
else
  python "$SCRIPT_DIR/namespace_aar.py" "$OUT_AAR"
fi
echo "Wrote $OUT_AAR"
ls -la "$OUT_AAR"
