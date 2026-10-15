#!/usr/bin/env bash
# Rebuilds android/app/libs/libv2ray.aar (VLESS engine, Xray-core) from the
# official AndroidLibXrayLite release: drops geoip/geosite assets (unused,
# ~28 MB) and the x86 ABI (not in abiFilters).
#
#   bash tools/fetch_libv2ray.sh            # default version below
#   bash tools/fetch_libv2ray.sh v26.10.10 <sha256-of-upstream-aar>
set -euo pipefail

VERSION="${1:-v26.10.10}"
SHA256="${2:-15db760bfbc24c0492ee997784b48a7b5e1bc5032950d617cd252fc2195f7ac7}"
URL="https://github.com/2dust/AndroidLibXrayLite/releases/download/${VERSION}/libv2ray.aar"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/android/app/libs/libv2ray.aar"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

curl -fsSL -o "$work/upstream.aar" "$URL"
echo "$SHA256  $work/upstream.aar" | sha256sum -c -

mkdir "$work/x"
unzip -q "$work/upstream.aar" -d "$work/x"
rm -rf "$work/x/assets" "$work/x/jni/x86"

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
(cd "$work/x" && zip -q -r -9 -X "$OUT" .)
echo "wrote $OUT ($(du -h "$OUT" | cut -f1))"
