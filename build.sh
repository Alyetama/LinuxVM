#!/bin/bash
# Builds LinuxVM.app: compiles with SwiftPM, assembles a .app bundle, and
# code-signs it with the com.apple.security.virtualization entitlement
# (ad-hoc signing is fine for running locally on Apple Silicon).
#
# Usage:
#   ./build.sh         # build + sign
#   ./build.sh run     # build + sign, then launch the app
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="LinuxVM"
BUNDLE="${APP_NAME}.app"
CONFIG="release"

echo "==> Compiling (${CONFIG})…"
swift build -c "${CONFIG}"
BIN_PATH="$(swift build -c "${CONFIG}" --show-bin-path)"
EXECUTABLE="${BIN_PATH}/${APP_NAME}"

if [[ ! -f "${EXECUTABLE}" ]]; then
  echo "error: built executable not found at ${EXECUTABLE}" >&2
  exit 1
fi

echo "==> Assembling ${BUNDLE}…"
rm -rf "${BUNDLE}"
mkdir -p "${BUNDLE}/Contents/MacOS"
mkdir -p "${BUNDLE}/Contents/Resources"

cp "${EXECUTABLE}" "${BUNDLE}/Contents/MacOS/${APP_NAME}"

# App icon. Regenerate if missing.
if [[ ! -f "Resources/AppIcon.icns" ]]; then
  echo "==> Generating app icon…"
  ./tools/make-icon.sh
fi
cp "Resources/AppIcon.icns" "${BUNDLE}/Contents/Resources/AppIcon.icns"

cat > "${BUNDLE}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>Linux VM</string>
    <key>CFBundleIdentifier</key><string>com.local.${APP_NAME}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "${BUNDLE}/Contents/PkgInfo"

echo "==> Code-signing (ad-hoc, with virtualization entitlement)…"
codesign --force --options runtime \
    --entitlements "${APP_NAME}.entitlements" \
    --sign - \
    "${BUNDLE}"

echo "==> Verifying signature…"
codesign --display --entitlements - "${BUNDLE}" 2>/dev/null | grep -q "com.apple.security.virtualization" \
    && echo "    virtualization entitlement present ✓"

echo ""
echo "Built: $(pwd)/${BUNDLE}"

if [[ "${1:-}" == "run" ]]; then
  echo "==> Launching…"
  open "${BUNDLE}"
elif [[ "${1:-}" == "install" ]]; then
  echo "==> Installing to /Applications…"
  rm -rf "/Applications/${BUNDLE}"
  cp -R "${BUNDLE}" "/Applications/${BUNDLE}"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/${BUNDLE}" 2>/dev/null || true
  echo "Installed: /Applications/${BUNDLE}"
else
  echo "Run it with:    open ${BUNDLE}"
  echo "Install it with: ./build.sh install"
fi
