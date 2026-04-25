#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: $(basename "$0") <addon-name>" >&2
    exit 1
fi

ADDON="$1"
ROOT="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$ROOT/.env"

if [[ ! -f "$ENV_FILE" ]]; then
    echo ".env not found at $ENV_FILE" >&2
    echo "expected: WOW_PATH=/path/to/World of Warcraft/_retail_/" >&2
    exit 1
fi

# Parse .env by hand instead of sourcing it, so values containing spaces
# (a common Windows install path) work without needing to be quoted.
WOW_PATH=""
while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    case "$line" in
        WOW_PATH=*)
            WOW_PATH="${line#WOW_PATH=}"
            WOW_PATH="${WOW_PATH#\"}"
            WOW_PATH="${WOW_PATH%\"}"
            ;;
    esac
done < "$ENV_FILE"

if [[ -z "$WOW_PATH" ]]; then
    echo "WOW_PATH not set in $ENV_FILE" >&2
    exit 1
fi

# Strip trailing slash so we can safely append a known suffix.
WOW_PATH="${WOW_PATH%/}"

SRC="$ROOT/$ADDON"
DEST="$WOW_PATH/Interface/AddOns"

if [[ ! -d "$SRC" ]]; then
    echo "source not found: $SRC" >&2
    exit 1
fi

if [[ ! -d "$DEST" ]]; then
    echo "destination not found: $DEST" >&2
    exit 1
fi

rm -rf "$DEST/$ADDON"
cp -r "$SRC" "$DEST/$ADDON"

echo "deployed $ADDON -> $DEST/$ADDON"
