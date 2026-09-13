#!/bin/bash
#
# Downloads what Stream URL needs to play web pages — YouTube and the other sites yt-dlp
# supports — and puts it in Vendor/Python/:
#
#   Python.xcframework           BeeWare's Python-Apple-support build of CPython for macOS,
#                                embedded in the app and run in-process
#   PythonSupport/yt-dlp.zip     the yt-dlp release the app ships with (it keeps itself up to
#                                date afterwards; this is only the starting point and fallback)
#   PythonSupport/cacert.pem     certifi's CA bundle: the embedded Python has no trust store
#
# Every download is pinned and checked against its published SHA-256, so a build can never pick
# up something else silently. To move to a newer version, change the version and its checksum
# together.
#
# Usage: ./scripts/download-python.sh

set -euo pipefail

PYTHON_TAG="3.14-b11"
PYTHON_ASSET="Python-3.14-macOS-support.b11.tar.gz"
PYTHON_SHA256="6b4c4e74128573c2330e579512e538fcc57b02df0748a0eae1b3e8922a71aac3"   # GitHub's asset digest

YTDLP_VERSION="2026.08.19"
YTDLP_SHA256="1fa6733c37ea6fb51c99ad8fe785e7b7e5f3246c9b980230329d4fb72ed8d4d6"    # the release's SHA2-256SUMS

CERTIFI_VERSION="2026.7.22"
CERTIFI_URL="https://files.pythonhosted.org/packages/0b/a7/71ac2cff56fec219ed242bb11b8efb69fcc4bec75db06fb7bfe35de520e6/certifi-2026.7.22-py3-none-any.whl"
CERTIFI_SHA256="62f22742b58a1a33014a2b6b706588a8d7e2a88ae7bd1a6ebe8c992928483775" # PyPI's digest

VENDOR_DIR="$(cd "$(dirname "$0")/.." && pwd)/Vendor/Python"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# fetch <url> <sha256> <destination>
fetch() {
    echo "Downloading $(basename "$3")…"
    curl -fL --retry 3 -o "$3" "$1"
    local got
    got=$(shasum -a 256 "$3" | cut -d' ' -f1)
    if [ "$got" != "$2" ]; then
        echo "error: checksum mismatch for $1" >&2
        echo "  expected $2" >&2
        echo "  got      $got" >&2
        exit 1
    fi
}

mkdir -p "$VENDOR_DIR/PythonSupport"

fetch "https://github.com/beeware/Python-Apple-support/releases/download/$PYTHON_TAG/$PYTHON_ASSET" \
      "$PYTHON_SHA256" "$TEMP_DIR/python.tar.gz"
tar -xzf "$TEMP_DIR/python.tar.gz" -C "$TEMP_DIR" Python.xcframework
STDLIB="$TEMP_DIR/Python.xcframework/macos-arm64_x86_64/Python.framework/Versions/3.14/lib/python3.14"
# Developer-only parts of the standard library: CPython's own test suite (37 MB), IDLE, the
# turtle demos and pip's bootstrapper. Nothing the app runs imports them.
rm -rf "$STDLIB/test" "$STDLIB/idlelib" "$STDLIB/turtledemo" "$STDLIB/ensurepip"
rm -rf "$VENDOR_DIR/Python.xcframework"
mv "$TEMP_DIR/Python.xcframework" "$VENDOR_DIR/"

fetch "https://github.com/yt-dlp/yt-dlp/releases/download/$YTDLP_VERSION/yt-dlp" \
      "$YTDLP_SHA256" "$VENDOR_DIR/PythonSupport/yt-dlp.zip"
echo "$YTDLP_VERSION" > "$VENDOR_DIR/PythonSupport/yt-dlp.version"

fetch "$CERTIFI_URL" "$CERTIFI_SHA256" "$TEMP_DIR/certifi.whl"
unzip -o -q "$TEMP_DIR/certifi.whl" certifi/cacert.pem -d "$TEMP_DIR"
cp "$TEMP_DIR/certifi/cacert.pem" "$VENDOR_DIR/PythonSupport/cacert.pem"

echo "Installed to Vendor/Python/: Python $PYTHON_TAG, yt-dlp $YTDLP_VERSION, certifi $CERTIFI_VERSION."
