#!/bin/bash
# Builds SiivOS and wraps it into a double-clickable app at dist/SiivOS.app.
# Optional: for day-to-day development, just press Run in Xcode instead.
#
# Usage (from the project folder):  ./Scripts/make-app.sh
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="SiivOS"
BUNDLE_ID="io.github.nikokorkalainen.SiivOS"
VERSION="0.1.0"
APP_DIR="dist/${APP_NAME}.app"

echo "Building ${APP_NAME}..."
swift build -c release --product "${APP_NAME}"
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp "${BIN_DIR}/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
cp "Resources/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

# Sign for this Mac only ("ad hoc"). A public release needs a Developer ID instead.
codesign --force --sign - "${APP_DIR}"

echo "Done: ${APP_DIR}"
