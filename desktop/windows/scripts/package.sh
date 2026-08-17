#!/usr/bin/env bash
# Build Windows amd64 host on Linux (CGO_ENABLED=0) and zip with pinned bins.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
BIN="$ROOT/bin"
mkdir -p "$DIST"
cd "$ROOT"
export CGO_ENABLED=0
export GOOS=windows
export GOARCH=amd64
go build -trimpath -ldflags="-s -w" -o "$DIST/teremok-host.exe" ./cmd/teremok-host
if [[ ! -f "$BIN/hysteria.exe" || ! -f "$BIN/wintun.dll" ]]; then
  bash "$ROOT/scripts/fetch-bins.sh"
fi
cp -f "$BIN/hysteria.exe" "$DIST/hysteria.exe"
cp -f "$BIN/wintun.dll" "$DIST/wintun.dll"
cp -f "$ROOT/README.md" "$DIST/README.txt"
STAGE="$DIST/teremok-windows-x64"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -f "$DIST/teremok-host.exe" "$DIST/hysteria.exe" "$DIST/wintun.dll" "$DIST/README.txt" "$STAGE/"
if [[ -f "$BIN/WINTUN-LICENSE.txt" ]]; then
  cp -f "$BIN/WINTUN-LICENSE.txt" "$STAGE/WINTUN-LICENSE.txt"
fi
(cd "$DIST" && if command -v zip >/dev/null 2>&1; then
  zip -qr teremok-windows-x64.zip teremok-windows-x64
else
  python3 -m zipfile -c teremok-windows-x64.zip teremok-windows-x64
fi)
echo "OK $DIST/teremok-windows-x64.zip"
ls -la "$DIST/teremok-windows-x64.zip" "$STAGE"
