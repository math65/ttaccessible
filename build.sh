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

# GitHub release (optional — pass --release to create one)
if [[ "$1" == "--release" ]]; then
    if ! command -v gh &> /dev/null; then
        echo "⚠ gh CLI not found — skipping GitHub release"
        exit 0
    fi

    TAG="v${VERSION}"
    TITLE="${APP_NAME} ${VERSION}"

    echo ""
    echo "==> Création de la release GitHub $TAG..."

    # Check if tag already exists
    if gh release view "$TAG" &> /dev/null; then
        echo "⚠ Release $TAG existe déjà. Mise à jour de l'asset..."
        gh release upload "$TAG" "$ZIP_PATH" --clobber
    else
        gh release create "$TAG" "$ZIP_PATH" \
            --title "$TITLE" \
            --notes "Release $VERSION. See [README](https://github.com/math65/ttaccessible#readme) for installation instructions." \
            --draft
        echo "✓ Release draft créée : https://github.com/math65/ttaccessible/releases/tag/$TAG"
        echo "  → Édite les notes de release sur GitHub puis publie-la."
    fi

    echo "✓ Asset uploadé : $ZIP_NAME"
fi
