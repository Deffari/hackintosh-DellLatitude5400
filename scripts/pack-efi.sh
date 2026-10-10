#!/usr/bin/env bash
# pack-efi.sh - build a distributable zip of the EFI folder.
#
# The zip contains EFI/BOOT/... and EFI/OC/... (the exact layout an EFI system
# partition needs). Unpack it straight into the mounted ESP:
#     macOS :  diskutil mount disk4s1 && unzip dist/EFI-<version>.zip -d /Volumes/EFI
#     Linux :  mount /dev/sdb1 /mnt/efi && unzip dist/EFI-<version>.zip -d /mnt/efi
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

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/EFI"
cp -a "$ROOT/BOOT" "$STAGE/EFI/BOOT"
cp -a "$ROOT/OC"   "$STAGE/EFI/OC"

cd "$STAGE"
# -y keeps symlinks/permissions metadata as-is, -r recurses, -X drops extra attributes.
zip -q -r -y -X "$ARCHIVE" EFI -x "*.DS_Store" "*__MACOSX*"

echo "built $ARCHIVE"
unzip -l "$ARCHIVE" | tail -3
echo
echo "Verify before flashing:"
echo "  python3 scripts/verify-efi.py --fetch-ocvalidate"
