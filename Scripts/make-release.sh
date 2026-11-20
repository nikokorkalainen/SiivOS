#!/bin/bash
# Builds SiivOS for both kinds of Mac and packs it into a ZIP that can be attached to a
# release on GitHub: dist/SiivOS-<version>.zip, with dist/release-notes.md to go with it.
#
# The app is not signed with an Apple Developer ID, which needs a paid account. macOS
# therefore refuses to open a downloaded copy until the person allows it in System
# Settings. The release notes written here say how.
#
# Usage (from the project folder, on a Mac with Xcode):  bash Scripts/make-release.sh 0.1.0
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-}"
if ! [[ "${VERSION}" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    echo "Give the version number, such as:  bash Scripts/make-release.sh 0.1.0" >&2
    exit 1
fi
if [ "$(uname -s)" != "Darwin" ]; then
    echo "This script needs a Mac." >&2
    exit 1
fi

APP="dist/SiivOS.app"
ZIP="dist/SiivOS-${VERSION}.zip"
NOTES="dist/release-notes.md"

SIIVOS_VERSION="${VERSION}" SIIVOS_UNIVERSAL=1 bash Scripts/make-app.sh

echo "Checking the app..."
codesign --verify --deep --strict "${APP}"
ARCHS="$(lipo -archs "${APP}/Contents/MacOS/SiivOS")"
echo "Built for: ${ARCHS}"
case "${ARCHS}" in
    *arm64*x86_64*|*x86_64*arm64*) ;;
    *)
        echo "The app was not built for both kinds of Mac. Nothing was packed." >&2
        exit 1
        ;;
esac

echo "Packing ${ZIP}..."
rm -f "${ZIP}"
# ditto keeps the app's signature and layout intact, which a plain zip may not.
ditto -c -k --sequesterRsrc --keepParent "${APP}" "${ZIP}"
SUM="$(shasum -a 256 "${ZIP}" | awk '{print $1}')"

cat > "${NOTES}" <<NOTES
## Installing

1. Download \`SiivOS-${VERSION}.zip\` below and double-click it to unpack it.
2. Drag **SiivOS** into your **Applications** folder.
3. Open it. macOS shows **"SiivOS" Not Opened** and says that Apple could not verify it is free of malware. That is expected: SiivOS is not signed with a paid Apple Developer ID. Click **Done**, not Move to Trash.
4. Allow it once:
   - **macOS 15 or newer:** open **System Settings**, **Privacy & Security**, scroll down to **Security**, and click **Open Anyway** next to the message about SiivOS. Confirm with your password or Touch ID.
   - **macOS 14:** hold Control and click SiivOS in Applications, choose **Open**, then **Open** again.

After that SiivOS opens like any other app. It needs macOS 14 or newer and runs on Macs with Apple chips and with Intel.

If you would rather not allow an unsigned app, build SiivOS yourself from the source code, as the README describes. It takes a few minutes.

## Checking the download

The SHA-256 of \`SiivOS-${VERSION}.zip\` is:

\`\`\`
${SUM}
\`\`\`

To compare, run \`shasum -a 256\` on the file you downloaded.
NOTES

SIZE="$(du -h "${ZIP}" | awk '{print $1}')"
echo
echo "Done: ${ZIP} (${SIZE})"
echo "SHA-256: ${SUM}"
echo "Notes for the release page: ${NOTES}"
