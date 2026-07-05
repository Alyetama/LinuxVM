#!/bin/bash
# Renders the app icon and packages it as Resources/AppIcon.icns.
set -euo pipefail
cd "$(dirname "$0")/.."

MASTER="/tmp/linuxvm_icon_1024.png"
ICONSET="/tmp/LinuxVM.iconset"

echo "==> Rendering master 1024px icon…"
swift tools/IconGen.swift "${MASTER}"

echo "==> Building iconset…"
rm -rf "${ICONSET}"; mkdir -p "${ICONSET}"
gen() { sips -z "$1" "$1" "${MASTER}" --out "${ICONSET}/$2" >/dev/null; }
gen 16   icon_16x16.png
gen 32   icon_16x16@2x.png
gen 32   icon_32x32.png
gen 64   icon_32x32@2x.png
gen 128  icon_128x128.png
gen 256  icon_128x128@2x.png
gen 256  icon_256x256.png
gen 512  icon_256x256@2x.png
gen 512  icon_512x512.png
cp "${MASTER}" "${ICONSET}/icon_512x512@2x.png"

echo "==> Converting to .icns…"
mkdir -p Resources
iconutil -c icns "${ICONSET}" -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns ($(du -h Resources/AppIcon.icns | cut -f1))"
