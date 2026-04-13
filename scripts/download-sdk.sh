#!/bin/bash
#
# Downloads the TeamTalk 5 SDK for macOS and extracts the files needed
# to build TTAccessible.
#
# Usage: ./scripts/download-sdk.sh
#
# Requirements: curl, 7z (p7zip)

set -euo pipefail

SDK_VERSION="v5.22a"
SDK_URL="https://www.bearware.dk/teamtalksdk/${SDK_VERSION}/tt5sdk_${SDK_VERSION}_macos_universal.7z"
SDK_ARCHIVE="tt5sdk_${SDK_VERSION}_macos_universal.7z"
SDK_DIR="tt5sdk_${SDK_VERSION}_macos_universal"

VENDOR_DIR="$(cd "$(dirname "$0")/../Vendor/TeamTalk" && pwd)"
TEMP_DIR=$(mktemp -d)

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Check for 7z
if ! command -v 7z &>/dev/null; then
    echo "Error: 7z is required. Install with: brew install p7zip"
    exit 1
fi

# Check if already present
if [ -f "$VENDOR_DIR/libTeamTalk5.dylib" ]; then
    echo "libTeamTalk5.dylib already exists in Vendor/TeamTalk/."
    read -p "Overwrite? [y/N] " answer
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
fi

echo "Downloading TeamTalk SDK ${SDK_VERSION}..."
curl -L -o "$TEMP_DIR/$SDK_ARCHIVE" "$SDK_URL"

echo "Extracting..."
7z x -o"$TEMP_DIR" "$TEMP_DIR/$SDK_ARCHIVE" \
    "${SDK_DIR}/Library/TeamTalk_DLL/libTeamTalk5.dylib" \
    "${SDK_DIR}/Library/TeamTalk_DLL/TeamTalk.h" \
    > /dev/null

echo "Installing to Vendor/TeamTalk/..."
cp "$TEMP_DIR/${SDK_DIR}/Library/TeamTalk_DLL/libTeamTalk5.dylib" "$VENDOR_DIR/"
cp "$TEMP_DIR/${SDK_DIR}/Library/TeamTalk_DLL/TeamTalk.h" "$VENDOR_DIR/"

echo ""
echo "Done. SDK ${SDK_VERSION} installed:"
ls -lh "$VENDOR_DIR/libTeamTalk5.dylib" "$VENDOR_DIR/TeamTalk.h"
