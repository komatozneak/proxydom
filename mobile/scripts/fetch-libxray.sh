#!/usr/bin/env bash
# Fetch prebuilt libXray.aar (gomobile) into android/app/libs/.
# Source: homa-games/libXray Maven mirror of XTLS/libXray.
# See docs/decisions/005-mobile-xray-core-migration.md
#
# HARD PIN: default 26.6.27. Do not bump past this without Marzban/VPS Xray
# lockstep + owner go. 26.7+ often fails Reality against our current server.
set -euo pipefail

PINNED="26.6.27"
VERSION="${LIBXRAY_VERSION:-$PINNED}"
if [[ "$VERSION" != "$PINNED" ]]; then
  echo "WARNING: libXray pin is ${PINNED}; requested ${VERSION} — ensure Marzban/VPS Xray was upgraded (owner go)." >&2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/android/app/libs/libXray.aar"
URL="https://raw.githubusercontent.com/homa-games/libXray/repo/repo/io/github/homa-games/libXray/${VERSION}/libXray-${VERSION}.aar"

mkdir -p "$(dirname "$OUT")"
echo "Downloading libXray ${VERSION} → ${OUT}"
curl -fL --retry 3 -o "$OUT" "$URL"
SIZE=$(wc -c < "$OUT" | tr -d ' ')
echo "OK: ${SIZE} bytes (pin policy: default ${PINNED})"
unzip -l "$OUT" | grep -E 'libgojni\.so|LibXray' | head -20
