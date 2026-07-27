#!/bin/bash
#
# Builds the Apple Help Book (Help/ttaccessible.help) from the Markdown sources
# in Help/Source/{en,fr}/ using pandoc, then indexes each localization with
# hiutil so Help Viewer search works.
#
# Usage: ./scripts/build-help-book.sh <marketing-version> <build-number>
#        ./scripts/build-help-book.sh --dev            (timestamp version, for local testing)
#
# The generated bundle is committed to the repository so that building the app
# never requires pandoc. Regenerate it whenever the Markdown sources change.
#
# CFBundleShortVersionString of the help bundle is the cache key used by helpd: it
# keys both ~/Library/Caches/com.apple.helpd/Generated/<bundle-id>*<version> and the
# private COPY of the whole book it keeps under ~/Library/Group Containers/
# group.com.apple.helpviewer.content/Library/Caches/. Same version + changed content
# ⇒ the viewer keeps serving the old pages. Bump the version on every content change,
# use --dev while writing, and run `sudo hiutil -P` before testing a rebuild — it is
# the only supported way to purge those caches without leaving helpd in a bad state.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_DIR="$ROOT_DIR/Help/Source"
BOOK="$ROOT_DIR/Help/ttaccessible.help"
TEMPLATE="$SCRIPT_DIR/help-book-template.html"
BUNDLE_ID="com.math65.ttaccessible.help"
INDEX_NAME="ttaccessible.cshelpindex"
# The legacy LSM index is still expected by the help viewer alongside the
# CoreSpotlight one — shipping only the latter leaves it unable to display the
# book at all (this is what OnyX and every working third-party book do).
LSM_INDEX_NAME="ttaccessible.helpindex"

LANGS=(en fr)

# Localized bundle title and "back to the table of contents" link label.
title_for() {
    case "$1" in
        en) echo "tt-Accessible Help" ;;
        fr) echo "Aide tt-Accessible" ;;
    esac
}

home_for() {
    case "$1" in
        en) echo "Table of contents" ;;
        fr) echo "Sommaire" ;;
    esac
}

# ---------------------------------------------------------------- arguments --

if [[ $# -eq 1 && "$1" == "--dev" ]]; then
    # helpd keys its caches on CFBundleShortVersionString — both
    # ~/Library/Caches/com.apple.helpd/Generated/<id>*<short-version> and the full
    # copy of the book it keeps under ~/Library/Group Containers/
    # group.com.apple.helpviewer.content — so the *short* version is what has to
    # vary while writing, not CFBundleVersion.
    MARKETING_VERSION="0.0.$(date +%s)"
    BUILD_NUMBER="$(date +%s)"
    echo "→ Dev build: version $MARKETING_VERSION (defeats the helpd cache)"
elif [[ $# -eq 2 ]]; then
    MARKETING_VERSION="$1"
    BUILD_NUMBER="$2"
else
    echo "Usage: $0 <marketing-version> <build-number>" >&2
    echo "       $0 --dev" >&2
    exit 2
fi

# -------------------------------------------------------------- validations --

if ! command -v pandoc &> /dev/null; then
    echo "✗ pandoc not found. Install with: brew install pandoc" >&2
    exit 1
fi

if [[ ! -x /usr/bin/hiutil ]]; then
    echo "✗ /usr/bin/hiutil not found (part of macOS)." >&2
    exit 1
fi

if [[ ! -f "$TEMPLATE" ]]; then
    echo "✗ Template not found: $TEMPLATE" >&2
    exit 1
fi

for lang in "${LANGS[@]}"; do
    if [[ ! -d "$SRC_DIR/$lang" ]]; then
        echo "✗ Missing source directory: $SRC_DIR/$lang" >&2
        exit 1
    fi
done

# The two localizations must expose exactly the same pages: the cross-language
# links and the HelpAnchor enum both depend on it.
en_pages="$(cd "$SRC_DIR/en" && ls -1 *.md | sort)"
for lang in "${LANGS[@]}"; do
    other_pages="$(cd "$SRC_DIR/$lang" && ls -1 *.md | sort)"
    if [[ "$en_pages" != "$other_pages" ]]; then
        echo "✗ Page mismatch between en/ and $lang/:" >&2
        diff <(echo "$en_pages") <(echo "$other_pages") >&2 || true
        exit 1
    fi
done

# ------------------------------------------------------------------- build ---

# Full rebuild: guarantees a fresh mtime on the bundle root so Xcode recopies it
# during an incremental build.
rm -rf "$BOOK"
mkdir -p "$BOOK/Contents/Resources/css" "$BOOK/Contents/Resources/shrd"

cat > "$BOOK/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleIdentifier</key>
	<string>$BUNDLE_ID</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$(title_for en)</string>
	<key>CFBundlePackageType</key>
	<string>BNDL</string>
	<key>CFBundleShortVersionString</key>
	<string>$MARKETING_VERSION</string>
	<key>CFBundleSignature</key>
	<string>hbwr</string>
	<key>CFBundleVersion</key>
	<string>$BUILD_NUMBER</string>
	<key>HPDBookAccessPath</key>
	<string>index.html</string>
	<key>HPDBookCSIndexPath</key>
	<string>$INDEX_NAME</string>
	<key>HPDBookIndexPath</key>
	<string>$LSM_INDEX_NAME</string>
	<key>HPDBookIconPath</key>
	<string>shrd/help-icon.png</string>
	<key>HPDBookKBProduct</key>
	<string>ttaccessible1</string>
	<key>HPDBookTitle</key>
	<string>$(title_for en)</string>
	<key>HPDBookType</key>
	<string>3</string>
</dict>
</plist>
PLIST

printf 'BNDLhbwr' > "$BOOK/Contents/PkgInfo"

cp "$SRC_DIR/shared/help.css" "$BOOK/Contents/Resources/css/help.css"
cp "$SRC_DIR/shared/help-icon.png" "$BOOK/Contents/Resources/shrd/help-icon.png"

for lang in "${LANGS[@]}"; do
    LPROJ="$BOOK/Contents/Resources/$lang.lproj"
    mkdir -p "$LPROJ"

    # Localized book title, read by Help Viewer through the standard bundle
    # localization mechanism.
    cat > "$LPROJ/InfoPlist.strings" <<STRINGS
/* Title of the help book as shown by Help Viewer */
"CFBundleName" = "$(title_for "$lang")";
"HPDBookTitle" = "$(title_for "$lang")";
STRINGS

    page_count=0
    for src in "$SRC_DIR/$lang"/*.md; do
        base="$(basename "$src" .md)"
        # 10-getting-started.md → getting-started.html
        out="${base#*-}.html"

        pandoc \
            --from=gfm+yaml_metadata_block \
            --to=html5 \
            --standalone \
            --wrap=none \
            --template="$TEMPLATE" \
            --metadata lang="$lang" \
            --metadata home="$(home_for "$lang")" \
            --output "$LPROJ/$out" \
            "$src"

        page_count=$((page_count + 1))
    done

    # -I corespotlight: the only index format macOS still reads (Mojave+).
    # -a: index anchors, required by NSHelpManager.openHelpAnchor(_:inBook:).
    # -m 3: minimum term length. -s/-l: stopword list and indexing locale, so a
    # French book indexes correctly from an English system.
    rm -f "$LPROJ/$INDEX_NAME" "$LPROJ/$LSM_INDEX_NAME"
    /usr/bin/hiutil \
        -I corespotlight \
        -Caf "$LPROJ/$INDEX_NAME" \
        -m 3 \
        -s "$lang" \
        -l "$lang" \
        "$LPROJ"
    /usr/bin/hiutil \
        -I lsm \
        -Caf "$LPROJ/$LSM_INDEX_NAME" \
        -m 3 \
        -s "$lang" \
        -l "$lang" \
        "$LPROJ"

    echo "✓ $lang.lproj — $page_count page(s) rendered and indexed"
done

find "$BOOK" -name '.DS_Store' -delete
plutil -lint "$BOOK/Contents/Info.plist" > /dev/null

# ------------------------------------------------------------------ checks ---

# 1. Every internal link must point at a page that exists. A typo would otherwise
#    only show up as a dead end in Help Viewer.
broken=0
for lang in "${LANGS[@]}"; do
    LPROJ="$BOOK/Contents/Resources/$lang.lproj"
    for page in "$LPROJ"/*.html; do
        while read -r target; do
            [[ -z "$target" ]] && continue
            # Strip the fragment, skip absolute URLs.
            path="${target%%#*}"
            [[ -z "$path" ]] && continue
            case "$path" in http*|mailto:*) continue ;; esac
            if [[ ! -f "$LPROJ/$path" ]]; then
                echo "✗ $lang.lproj/$(basename "$page"): dead link → $target" >&2
                broken=1
            fi
        done < <(grep -o 'href="[^"]*"' "$page" | sed 's/href="//; s/"$//')
    done
done

# 2. Every case of HelpAnchor must resolve to an indexed anchor, in both
#    languages — otherwise NSHelpManager silently lands on nothing.
HELP_BOOK_SWIFT="$ROOT_DIR/App/ttaccessible/Services/HelpBook.swift"
if [[ -f "$HELP_BOOK_SWIFT" ]]; then
    # `index` is the home page: it is reached through HPDBookAccessPath, not an anchor.
    anchors=$(grep -oE '^\s*case [a-zA-Z]+ = "[^"]+"' "$HELP_BOOK_SWIFT" \
        | sed 's/.*= "//; s/"//' | grep -v '^help-index$')
    for lang in "${LANGS[@]}"; do
        indexed=$(/usr/bin/hiutil -I corespotlight -Af \
            "$BOOK/Contents/Resources/$lang.lproj/$INDEX_NAME")
        while read -r anchor; do
            [[ -z "$anchor" ]] && continue
            if ! grep -qx "$anchor" <<< "$indexed"; then
                echo "✗ $lang.lproj: HelpAnchor \"$anchor\" is not in the search index" >&2
                broken=1
            fi
        done <<< "$anchors"
    done
fi

if [[ $broken -ne 0 ]]; then
    echo "✗ Help book built, but the checks above failed." >&2
    exit 1
fi
echo "✓ Links and HelpAnchor cases check out"

echo "✓ Built $BOOK (version $MARKETING_VERSION, build $BUILD_NUMBER)"
echo
echo "  Test with:  sudo hiutil -P   # purge the Help Viewer cache"
echo "              open 'help:openbook=\"$BUNDLE_ID\"'   # after building the app"
