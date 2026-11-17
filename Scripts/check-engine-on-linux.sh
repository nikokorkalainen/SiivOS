#!/bin/bash
# Compiles the engine (SiivOSCore) and runs its tests on Linux.
#
# This is for Claude's cloud workspace, which is Linux and cannot build the Mac app.
# It catches mistakes in the engine before the code reaches a Mac. The SwiftUI app in
# Sources/SiivOS is only checked for syntax slips such as a missing bracket.
#
# The first run downloads the official Swift toolchain (about 900 MB) from
# download.swift.org and checks its signature. Later runs reuse it.
#
# Usage (from the project folder):  ./Scripts/check-engine-on-linux.sh
set -euo pipefail

cd "$(dirname "$0")/.."
PROJECT_DIR="$(pwd)"

SWIFT_VERSION="6.1.2"
PLATFORM="ubuntu24.04"
CACHE_DIR="${SIIVOS_TOOLCHAIN_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/siivos-swift}"
TOOLCHAIN_NAME="swift-${SWIFT_VERSION}-RELEASE-${PLATFORM}"
TOOLCHAIN_DIR="${CACHE_DIR}/${TOOLCHAIN_NAME}"

if [ "$(uname -s)" != "Linux" ]; then
    echo "This script is for Linux. On a Mac, run: swift test" >&2
    exit 1
fi

if [ ! -x "${TOOLCHAIN_DIR}/usr/bin/swift" ]; then
    if [ "$(uname -m)" != "x86_64" ] || ! grep -q 'VERSION_ID="24.04"' /etc/os-release; then
        echo "This script only knows how to install Swift on Ubuntu 24.04 (x86_64)." >&2
        exit 1
    fi
    echo "Downloading Swift ${SWIFT_VERSION}..."
    mkdir -p "${CACHE_DIR}"
    DOWNLOAD_DIR="$(mktemp -d "${CACHE_DIR}/download.XXXXXX")"
    trap 'rm -rf "${DOWNLOAD_DIR}"' EXIT
    URL="https://download.swift.org/swift-${SWIFT_VERSION}-release/${PLATFORM//./}/swift-${SWIFT_VERSION}-RELEASE/${TOOLCHAIN_NAME}.tar.gz"
    curl -fsS --retry 3 -o "${DOWNLOAD_DIR}/swift.tar.gz" "${URL}"
    curl -fsS --retry 3 -o "${DOWNLOAD_DIR}/swift.tar.gz.sig" "${URL}.sig"
    curl -fsS --retry 3 -o "${DOWNLOAD_DIR}/keys.asc" "https://www.swift.org/keys/all-keys.asc"

    echo "Checking the download's signature..."
    mkdir -m 700 "${DOWNLOAD_DIR}/gnupg"
    gpg --homedir "${DOWNLOAD_DIR}/gnupg" --quiet --import "${DOWNLOAD_DIR}/keys.asc" 2>/dev/null
    if ! gpg --homedir "${DOWNLOAD_DIR}/gnupg" --verify \
        "${DOWNLOAD_DIR}/swift.tar.gz.sig" "${DOWNLOAD_DIR}/swift.tar.gz" 2>&1 | grep -q "Good signature"; then
        echo "The Swift download did not pass its signature check. Nothing was installed." >&2
        exit 1
    fi

    tar -xzf "${DOWNLOAD_DIR}/swift.tar.gz" -C "${DOWNLOAD_DIR}"
    mv "${DOWNLOAD_DIR}/${TOOLCHAIN_NAME}" "${TOOLCHAIN_DIR}"
fi
export PATH="${TOOLCHAIN_DIR}/usr/bin:${PATH}"

# Build a copy that contains only the engine and its tests, because the app target
# needs SwiftUI and AppKit, which do not exist on Linux. The project is not changed.
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}" "${DOWNLOAD_DIR:-}"' EXIT
mkdir -p "${WORK_DIR}/Sources"
cp -R "${PROJECT_DIR}/Sources/SiivOSCore" "${WORK_DIR}/Sources/SiivOSCore"
cp -R "${PROJECT_DIR}/Tests" "${WORK_DIR}/Tests"
cat > "${WORK_DIR}/Package.swift" <<'MANIFEST'
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SiivOS",
    targets: [
        .target(name: "SiivOSCore"),
        .testTarget(name: "SiivOSCoreTests", dependencies: ["SiivOSCore"])
    ]
)
MANIFEST

swift --version

echo "Checking the app's syntax..."
swiftc -parse "${PROJECT_DIR}"/Sources/SiivOS/*.swift

cd "${WORK_DIR}"
swift test
