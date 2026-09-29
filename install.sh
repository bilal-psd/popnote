#!/bin/sh
# Installs or updates Popnote:
#
#   curl -fsSL https://raw.githubusercontent.com/bilal-psd/popnote/main/install.sh | sh
#
# Downloads the latest release into /Applications (or ~/Applications if
# /Applications isn't writable) and opens it.
set -e

URL=https://github.com/bilal-psd/popnote/releases/latest/download/Popnote.zip
APP_ID=io.github.bilal-psd.popnote

major=$(sw_vers -productVersion | cut -d. -f1)
if [ "$major" -lt 14 ]; then
    echo "Popnote needs macOS 14 (Sonoma) or later." >&2
    exit 1
fi

DEST=/Applications
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Downloading Popnote…"
curl -fsSL "$URL" -o "$TMP/Popnote.zip"
ditto -x -k "$TMP/Popnote.zip" "$TMP"

# Quit a running copy so it can be replaced. Notes are saved as you type.
osascript -e "if application id \"$APP_ID\" is running then tell application id \"$APP_ID\" to quit" >/dev/null 2>&1 || true
sleep 1

rm -rf "$DEST/Popnote.app"
ditto "$TMP/Popnote.app" "$DEST/Popnote.app"
echo "Installed Popnote in $DEST"
open "$DEST/Popnote.app"
