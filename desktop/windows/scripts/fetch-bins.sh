#!/usr/bin/env bash
# Download pinned hysteria.exe + wintun.dll. Does not compile Hy2.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/bin"
SUMS="$ROOT/SHA256SUMS"
HYSTERIA_ASSET="hysteria-windows-amd64.exe"
HYSTERIA_BASE="https://github.com/apernet/hysteria/releases/download/app%2Fv2.6.2"
WINTUN_ZIP_URL="https://www.wintun.net/builds/wintun-0.14.1.zip"

pinned_sha() {
  local name="$1"
  awk -v n="$name" '
    $0 ~ /^[0-9a-f]{64}[ \t]+/ && $2 == n { print $1; exit }
  ' "$SUMS"
}

HY_PIN="$(pinned_sha "$HYSTERIA_ASSET")"
WINTUN_ZIP_SHA="$(pinned_sha "wintun-0.14.1.zip")"
if [[ -z "$HY_PIN" || -z "$WINTUN_ZIP_SHA" ]]; then
  echo "SHA256SUMS missing pins" >&2
  exit 1
fi

mkdir -p "$BIN"
cd "$BIN"

echo "=== fetch hysteria app/v2.6.2 ==="
curl -fsSL -o hashes.txt "${HYSTERIA_BASE}/hashes.txt"
HY_LINE="$(grep -E "[[:space:]](build/)?${HYSTERIA_ASSET}$" hashes.txt | grep -v -- '-avx' | tail -n1 || true)"
if [[ -z "$HY_LINE" ]]; then
  echo "hashes.txt has no ${HYSTERIA_ASSET}" >&2
  cat hashes.txt >&2
  exit 1
fi
HY_SHA="$(echo "$HY_LINE" | awk '{print $1}')"
if [[ "$HY_SHA" != "$HY_PIN" ]]; then
  echo "hashes.txt ${HY_SHA} != SHA256SUMS pin ${HY_PIN}" >&2
  exit 1
fi

curl -fsSL -o "$HYSTERIA_ASSET" "${HYSTERIA_BASE}/${HYSTERIA_ASSET}"
echo "${HY_PIN}  ${HYSTERIA_ASSET}" | sha256sum -c -
cp -f "$HYSTERIA_ASSET" hysteria.exe

echo "=== fetch wintun 0.14.1 amd64 ==="
curl -fsSL -o wintun-0.14.1.zip "$WINTUN_ZIP_URL"
echo "${WINTUN_ZIP_SHA}  wintun-0.14.1.zip" | sha256sum -c -
rm -rf wintun-extract
mkdir wintun-extract
unzip -q -o wintun-0.14.1.zip -d wintun-extract
cp -f wintun-extract/wintun/bin/amd64/wintun.dll wintun.dll
WINTUN_DLL_SHA="$(pinned_sha "wintun.dll")"
if [[ -n "$WINTUN_DLL_SHA" ]]; then
  echo "${WINTUN_DLL_SHA}  wintun.dll" | sha256sum -c -
fi
if [[ -f wintun-extract/wintun/LICENSE.txt ]]; then
  cp -f wintun-extract/wintun/LICENSE.txt WINTUN-LICENSE.txt
fi
rm -rf wintun-extract wintun-0.14.1.zip hashes.txt "$HYSTERIA_ASSET"

echo "OK $BIN/hysteria.exe $BIN/wintun.dll"
ls -la hysteria.exe wintun.dll
