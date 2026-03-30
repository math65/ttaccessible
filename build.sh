#!/bin/bash
set -e

SCHEME="ttaccessible"
PROJECT="App/ttaccessible.xcodeproj"
CONFIGURATION="Release"
DERIVED_DATA="/tmp/ttaccessible-build"
APP_NAME="ttaccessible"
OUTPUT_DIR="$(dirname "$0")/BuildArtifacts"

echo "==> Build $SCHEME ($CONFIGURATION)..."
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED_DATA" \
    build

APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"

echo "==> Copie vers /Applications..."
rm -rf "/Applications/$APP_NAME.app"
cp -R "$APP_PATH" "/Applications/$APP_NAME.app"

mkdir -p "$OUTPUT_DIR"
VERSION=$(defaults read "$APP_PATH/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "1.0")
BUILD=$(defaults read "$APP_PATH/Contents/Info" CFBundleVersion 2>/dev/null || echo "1")
ZIP_NAME="${APP_NAME}-${VERSION}-${BUILD}.zip"
ZIP_PATH="$OUTPUT_DIR/$ZIP_NAME"

echo "==> Création du zip $ZIP_NAME..."
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo ""
echo "✓ /Applications/$APP_NAME.app"
echo "✓ $ZIP_PATH"
