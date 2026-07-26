#!/bin/bash
set -e

SCHEME="ttaccessible"
PROJECT="App/ttaccessible.xcodeproj"
CONFIGURATION="Release"
DERIVED_DATA="/tmp/ttaccessible-build"
APP_NAME="ttaccessible"
OUTPUT_DIR="$(dirname "$0")/BuildArtifacts"
SIGN_IDENTITY="Developer ID Application: Mathieu Martin (633EG76YX5)"
NOTARY_PROFILE="ttaccessible-notary"
ENTITLEMENTS="App/ttaccessible/ttaccessible.entitlements"

NOTARIZE=0
RELEASE=0
BETA=0
for arg in "$@"; do
    case "$arg" in
        --notarize) NOTARIZE=1 ;;
        --release)  NOTARIZE=1; RELEASE=1 ;;
        # Publish to the Sparkle "beta" channel: the appcast item is tagged
        # <sparkle:channel>beta</sparkle:channel> (only delivered to users who
        # enabled "Include beta versions") and the GitHub release is marked as a
        # prerelease. Use together with --release, e.g. ./build.sh --release --beta
        --beta)     BETA=1 ;;
    esac
done

if [[ $BETA -eq 1 ]]; then
    echo "==> Mode BETA : appcast taggé 'beta', release GitHub en prerelease"
fi

echo "==> Build $SCHEME ($CONFIGURATION)..."
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED_DATA" \
    -allowProvisioningUpdates \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    build

APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"

if [[ $NOTARIZE -eq 1 ]]; then
    echo "==> Signature Developer ID..."

    # Sparkle.framework contient des binaires et bundles nichés qui doivent être
    # signés individuellement (deepest-first) avant la framework elle-même.
    SPARKLE_FW="$APP_PATH/Contents/Frameworks/Sparkle.framework"
    if [[ -d "$SPARKLE_FW" ]]; then
        for nested in \
            "$SPARKLE_FW/Versions/B/XPCServices/Downloader.xpc" \
            "$SPARKLE_FW/Versions/B/XPCServices/Installer.xpc" \
            "$SPARKLE_FW/Versions/B/Autoupdate" \
            "$SPARKLE_FW/Versions/B/Updater.app"
        do
            if [[ -e "$nested" ]]; then
                codesign --force --options runtime --timestamp \
                    --sign "$SIGN_IDENTITY" "$nested"
            fi
        done
    fi

    find "$APP_PATH/Contents" \( -name "*.dylib" -o -name "*.framework" \) -print0 | \
        while IFS= read -r -d '' nested; do
            codesign --force --options runtime --timestamp \
                --sign "$SIGN_IDENTITY" "$nested"
        done
    codesign --force --options runtime --timestamp \
        --entitlements "$ENTITLEMENTS" \
        --sign "$SIGN_IDENTITY" "$APP_PATH"

    echo "==> Vérification de la signature..."
    codesign --verify --strict --verbose=2 "$APP_PATH"
fi

mkdir -p "$OUTPUT_DIR"
VERSION=$(defaults read "$APP_PATH/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "1.0")
BUILD=$(defaults read "$APP_PATH/Contents/Info" CFBundleVersion 2>/dev/null || echo "1")
ZIP_NAME="${APP_NAME}-${VERSION}-${BUILD}.zip"
ZIP_PATH="$OUTPUT_DIR/$ZIP_NAME"

echo "==> Création du zip $ZIP_NAME..."
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

if [[ $NOTARIZE -eq 1 ]]; then
    echo "==> Soumission à Apple notarytool (peut prendre 5-30 min)..."
    xcrun notarytool submit "$ZIP_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait

    echo "==> Stapler le ticket au .app..."
    xcrun stapler staple "$APP_PATH"

    echo "==> Vérification Gatekeeper..."
    spctl --assess --type execute --verbose=2 "$APP_PATH" || true

    echo "==> Re-création du zip avec ticket stapled..."
    rm -f "$ZIP_PATH"
    ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

    echo "==> Génération de l'appcast Sparkle..."
    SPARKLE_BIN="$DERIVED_DATA/SourcePackages/artifacts/sparkle/Sparkle/bin"
    if [[ ! -x "$SPARKLE_BIN/generate_appcast" ]]; then
        echo "✗ Outils Sparkle introuvables à $SPARKLE_BIN"
        echo "  (résolus normalement par xcodebuild lors du build)"
        exit 1
    fi

    APPCAST_STAGING="$(dirname "$0")/.appcast-staging"
    rm -rf "$APPCAST_STAGING"
    mkdir -p "$APPCAST_STAGING"
    cp "$ZIP_PATH" "$APPCAST_STAGING/"

    DOCS_DIR="$(dirname "$0")/docs"
    mkdir -p "$DOCS_DIR"

    # Release notes sidecar — render RELEASE_NOTES.md to HTML so Sparkle's
    # WKWebView gets styled content (light + dark mode) instead of raw Markdown.
    # The .html lives in docs/ (GitHub Pages); the .md stays at repo root for
    # `gh release create --notes-file` further down.
    ZIP_BASENAME="${ZIP_NAME%.zip}"
    if [[ -f "$(dirname "$0")/RELEASE_NOTES.md" ]]; then
        "$(dirname "$0")/scripts/render-release-notes.sh" \
            "$(dirname "$0")/RELEASE_NOTES.md" \
            "$DOCS_DIR/${ZIP_BASENAME}.html" \
            "en"
        cp "$DOCS_DIR/${ZIP_BASENAME}.html" "$APPCAST_STAGING/${ZIP_BASENAME}.html"
    fi
    # Localized (French) release notes. generate_appcast picks up the
    # <basename>.<lang>.html sidecar and emits a matching
    # <sparkle:releaseNotesLink xml:lang="fr">; Sparkle then shows it to
    # French users and falls back to the unsuffixed .html for everyone else.
    if [[ -f "$(dirname "$0")/RELEASE_NOTES.fr.md" ]]; then
        "$(dirname "$0")/scripts/render-release-notes.sh" \
            "$(dirname "$0")/RELEASE_NOTES.fr.md" \
            "$DOCS_DIR/${ZIP_BASENAME}.fr.html" \
            "fr"
        cp "$DOCS_DIR/${ZIP_BASENAME}.fr.html" "$APPCAST_STAGING/${ZIP_BASENAME}.fr.html"
    fi
    # Preserve existing entries by copying current appcast into staging
    if [[ -f "$DOCS_DIR/appcast.xml" ]]; then
        cp "$DOCS_DIR/appcast.xml" "$APPCAST_STAGING/appcast.xml"
    fi

    # Tag only the freshly-generated item with the beta channel. Existing
    # entries preserved from the copied-in appcast keep their channel (none =
    # stable), so stable users never see the beta build.
    CHANNEL_ARGS=()
    if [[ $BETA -eq 1 ]]; then
        CHANNEL_ARGS+=(--channel beta)
    fi

    "$SPARKLE_BIN/generate_appcast" \
        "$APPCAST_STAGING" \
        "${CHANNEL_ARGS[@]}" \
        --download-url-prefix "https://github.com/math65/ttaccessible/releases/download/v${VERSION}/" \
        --link "https://github.com/math65/ttaccessible/releases/tag/v${VERSION}" \
        -o "$DOCS_DIR/appcast.xml"

    # generate_appcast emits the unsuffixed (English) <sparkle:releaseNotesLink>
    # WITHOUT an xml:lang. When a localized (fr) sibling is present Sparkle warns
    # "one of them does not have xml:lang specified". Tag the untagged English
    # links explicitly as xml:lang="en" to silence it.
    sed -i '' 's#<sparkle:releaseNotesLink>#<sparkle:releaseNotesLink xml:lang="en">#g' "$DOCS_DIR/appcast.xml"

    rm -rf "$APPCAST_STAGING"
    echo "✓ docs/appcast.xml généré"
fi

echo ""
echo "✓ $ZIP_PATH"

if [[ $RELEASE -eq 1 ]]; then
    if ! command -v gh &> /dev/null; then
        echo "⚠ gh CLI not found — skipping GitHub release"
        exit 0
    fi

    TAG="v${VERSION}"
    TITLE="${APP_NAME} ${VERSION}"

    echo ""
    echo "==> Création de la release GitHub $TAG..."

    NOTES_FILE="$(dirname "$0")/RELEASE_NOTES.md"
    if [[ ! -f "$NOTES_FILE" ]]; then
        echo "✗ RELEASE_NOTES.md introuvable à la racine — abandon de la release GitHub."
        exit 1
    fi

    PRERELEASE_ARGS=()
    if [[ $BETA -eq 1 ]]; then
        PRERELEASE_ARGS+=(--prerelease)
    fi

    if gh release view "$TAG" &> /dev/null; then
        echo "⚠ Release $TAG existe déjà. Mise à jour de l'asset..."
        gh release upload "$TAG" "$ZIP_PATH" --clobber
    else
        gh release create "$TAG" "$ZIP_PATH" \
            --title "$TITLE" \
            --notes-file "$NOTES_FILE" \
            "${PRERELEASE_ARGS[@]}"
        echo "✓ Release publiée : https://github.com/math65/ttaccessible/releases/tag/$TAG"
    fi

    echo "✓ Asset uploadé : $ZIP_NAME"

    # Push docs/ updates (appcast + release notes) — uniquement depuis main
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    if [[ "$CURRENT_BRANCH" == "main" ]]; then
        # Catch both tracked-with-changes and untracked-but-new files under docs/
        if [[ -n "$(git status --porcelain -- docs/)" ]]; then
            git add docs/appcast.xml "docs/${ZIP_BASENAME}.html" "docs/${ZIP_BASENAME}.fr.html" 2>/dev/null
            git commit -m "Update appcast and release notes for v${VERSION}"
            git push origin main
            echo "✓ Appcast + release notes pushés sur main"
        else
            echo "⚠ Aucun changement dans docs/ — rien à pousser"
        fi
    else
        echo "⚠ Branche $CURRENT_BRANCH != main : appcast régénéré localement mais non pushé"
        echo "  Mergez sur main avant de relancer --release pour publier l'appcast."
    fi
fi
