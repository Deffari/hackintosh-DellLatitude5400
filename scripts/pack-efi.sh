#!/usr/bin/env bash
# pack-efi.sh - build a distributable zip of the EFI folder.
#
# The zip contains BOOT/ and OC/ at the top level, which is exactly the layout the
# EFI system partition (ESP) of a USB flash drive needs. Copy it with:
#     macOS :  unzip dist/EFI-<version>.zip -d /Volumes/EFI
#     Linux :  unzip dist/EFI-<version>.zip -d /mnt/efi
#
# Usage: ./scripts/pack-efi.sh [output-directory]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-$ROOT/dist}"

VERSION="$(python3 - "$ROOT/components.lock" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))["opencore_version"])
PY
)"
ARCHIVE="$OUT_DIR/EFI-OpenCore-${VERSION}.zip"

mkdir -p "$OUT_DIR"
rm -f "$ARCHIVE"

cd "$ROOT"
# -y keeps symlinks/permissions metadata as-is, -r recurses, -X drops extra attributes.
zip -q -r -y -X "$ARCHIVE" BOOT OC -x "*.DS_Store" "*__MACOSX*"

echo "built $ARCHIVE"
unzip -l "$ARCHIVE" | tail -3
echo
echo "Verify before flashing:"
echo "  python3 scripts/verify-efi.py --fetch-ocvalidate"
