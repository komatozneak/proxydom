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
#   HYSTERIA_TAG=v2.6.2 bash build-aar.sh
set -euo pipefail

HYSTERIA_TAG="${HYSTERIA_TAG:-v2.6.2}"
OUT_DIR="$(cd "$(dirname "$0")/../app/libs" && pwd)"
OUT_AAR="$OUT_DIR/hysteria-client.aar"

echo "=== hy2bind gomobile (hysteria $HYSTERIA_TAG) ==="
go get "github.com/apernet/hysteria/core/v2@${HYSTERIA_TAG}"
# Go 1.25+: gomobile bind needs x/mobile in this module's tool graph.
go get -tool golang.org/x/mobile/cmd/gobind
go mod tidy
gomobile bind -v -target=android -androidapi=26 -o "$OUT_AAR" .
# libXray already owns go.Seq + libgojni.so. Relocate this AAR or AGP fails
# checkDebugDuplicateClasses.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if command -v python3 >/dev/null 2>&1; then
  python3 "$SCRIPT_DIR/namespace_aar.py" "$OUT_AAR"
else
  python "$SCRIPT_DIR/namespace_aar.py" "$OUT_AAR"
fi
echo "Wrote $OUT_AAR"
ls -la "$OUT_AAR"
