#!/bin/bash
# Builds SiivOS and wraps it into a double-clickable app at dist/SiivOS.app.
# Optional: for day-to-day development, just press Run in Xcode instead.
#
# Usage (from the project folder):  ./Scripts/make-app.sh
#
# Scripts/make-release.sh uses this too, with two things set:
#   SIIVOS_VERSION    the version number the app carries, in place of the one below
#   SIIVOS_UNIVERSAL  1 to build for both kinds of Mac (Apple chips and Intel) in one app.
#                     That needs Xcode itself, not only its command-line tools.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="SiivOS"
BUNDLE_ID="io.github.nikokorkalainen.SiivOS"
VERSION="${SIIVOS_VERSION:-0.1.0}"
APP_DIR="dist/${APP_NAME}.app"
CLI_NAME="siivos-cli"

BUILD_FLAGS=(-c release)
if [ "${SIIVOS_UNIVERSAL:-0}" = "1" ]; then
    BUILD_FLAGS+=(--arch arm64 --arch x86_64)
fi

echo "Building ${APP_NAME} ${VERSION}..."
swift build "${BUILD_FLAGS[@]}" --product "${APP_NAME}"
# The agent door: a read-only command-line tool for AI agents, kept inside the app.
swift build "${BUILD_FLAGS[@]}" --product "${CLI_NAME}"
BIN_DIR="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)"

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp "${BIN_DIR}/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
mkdir -p "${APP_DIR}/Contents/Helpers"
cp "${BIN_DIR}/${CLI_NAME}" "${APP_DIR}/Contents/Helpers/${CLI_NAME}"
cp "Resources/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"

# Compile the accent colour (moss green), which macOS uses for the selected sidebar row,
# tick boxes and focus rings. This needs Xcode. Without it the app still builds and works,
# with the Mac's own accent colour.
if xcrun --find actool >/dev/null 2>&1; then
    ASSET_INFO="$(mktemp)"
    if ASSET_OUTPUT="$(xcrun actool "Resources/Assets.xcassets" \
        --compile "${APP_DIR}/Contents/Resources" \
        --platform macosx \
        --target-device mac \
        --minimum-deployment-target 14.0 \
        --accent-color AccentColor \
        --output-partial-info-plist "${ASSET_INFO}" \
        --output-format human-readable-text 2>&1)"; then
        echo "Accent colour added."
    else
        echo "Note: the accent colour could not be added, so the Mac's own accent colour is used."
        echo "${ASSET_OUTPUT}"
    fi
    rm -f "${ASSET_INFO}"
else
    echo "Note: Xcode's asset tool was not found, so the Mac's own accent colour is used."
fi

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
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>fi</string>
    </array>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSAccentColorName</key>
    <string>AccentColor</string>
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
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Niko Korkalainen. Free software under the GNU General Public License, version 3 or later.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

# Sign for this Mac only ("ad hoc"). A public release needs a Developer ID instead.
codesign --force --sign - "${APP_DIR}/Contents/Helpers/${CLI_NAME}"
codesign --force --sign - "${APP_DIR}"

echo "Done: ${APP_DIR}"
