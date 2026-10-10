#!/usr/bin/env bash
# make-usb-linux.sh - build the Hackintosh USB flash drive from Linux.
#
# Layout written to the stick:
#   partition 1 (200 MB, EFI)      -> BOOT/ + OC/ from this repository  (OpenCore, boots always)
#   partition 2 (rest, FAT32)      -> optional offline installer (--recovery)
#
# Usage:
#   sudo ./scripts/make-usb-linux.sh --disk /dev/sdX
#   sudo ./scripts/make-usb-linux.sh --disk /dev/sdX --recovery 15      # macOS 15 Sequoia BaseSystem
#   sudo ./scripts/make-usb-linux.sh --disk /dev/sdX --recovery 26      # macOS 26 Tahoe BaseSystem
#
# WARNING: the whole disk is repartitioned. Check `lsblk` first.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DISK=""
RECOVERY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --disk) DISK="${2:-}"; shift 2 ;;
    --recovery) RECOVERY="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ -n "$DISK" ]] || { echo "--disk is required (e.g. --disk /dev/sdb)" >&2; exit 1; }
[[ "$DISK" =~ ^/dev/(sd[a-z]+|nvme[0-9]+n[0-9]+|mmcblk[0-9]+)$ ]] || {
  echo "refusing: $DISK does not look like a whole block device (no partition suffix)" >&2; exit 1; }
[[ -b "$DISK" ]] || { echo "$DISK is not a block device" >&2; exit 1; }
[[ "$(id -u)" == "0" ]] || { echo "run me with sudo" >&2; exit 1; }
[[ -d "$ROOT/OC" && -d "$ROOT/BOOT" ]] || { echo "run this from the repository" >&2; exit 1; }

for tool in sgdisk mkfs.vfat mount umount lsblk; do
  command -v "$tool" >/dev/null || { echo "missing tool: $tool (install gdisk, dosfstools, util-linux)" >&2; exit 1; }
done

# root disk protection: refuse if any mounted filesystem lives on this disk
if lsblk -no MOUNTPOINT "$DISK" 2>/dev/null | grep -qE '^/($|boot|home|usr)'; then
  echo "refusing: $DISK holds a mounted system filesystem" >&2
  exit 1
fi

echo "==> target: $DISK"
lsblk -o NAME,SIZE,MODEL,TRAN "$DISK" || true
echo "==> press ENTER to repartition $DISK, Ctrl-C to abort"; read -r _

part() { # partition device name for index $1
  case "$DISK" in
    *[0-9]) echo "${DISK}p$1" ;;
    *)      echo "${DISK}$1" ;;
  esac
}
ESP="$(part 1)"
DATA="$(part 2)"

echo "==> creating GPT + 200 MB EFI partition"
sgdisk --zap-all "$DISK"
sgdisk -n 1:2048:+200M -t 1:ef00 -c 1:"EFI" "$DISK"
sgdisk -n 2:0:0 -t 2:0700 -c 2:"INSTALLER" "$DISK" >/dev/null
partprobe "$DISK" 2>/dev/null || sleep 2

echo "==> formatting"
mkfs.vfat -F32 -n EFI "$ESP" >/dev/null
mkfs.vfat -F32 -n INSTALLER "$DATA" >/dev/null

MNT="$(mktemp -d)"
cleanup() { umount "$MNT" 2>/dev/null || true; rmdir "$MNT" 2>/dev/null || true; }
trap cleanup EXIT

mount "$ESP" "$MNT"
mkdir -p "$MNT/EFI"
cp -a "$ROOT/BOOT" "$MNT/EFI/BOOT"
cp -a "$ROOT/OC"   "$MNT/EFI/OC"
sync
echo "==> EFI partition contents:"; ls -1 "$MNT/EFI"
umount "$MNT"

if [[ -n "$RECOVERY" ]]; then
  echo "==> fetching macOS $RECOVERY recovery (BaseSystem) with OpenCore's macrecovery"
  WORK="$(mktemp -d)"
  VERSION="$(python3 -c "import json;print(json.load(open('$ROOT/components.lock'))['opencore_version'])")"
  curl -fsSL -o "$WORK/oc.zip" \
    "https://github.com/acidanthera/OpenCorePkg/releases/download/$VERSION/OpenCore-$VERSION-RELEASE.zip"
  unzip -q "$WORK/oc.zip" 'Utilities/macrecovery/*' -d "$WORK"
  mkdir -p "$WORK/recovery/com.apple.recovery.boot"
  python3 "$WORK/Utilities/macrecovery/macrecovery.py" \
    -b "$RECOVERY" -d "$WORK/recovery/com.apple.recovery.boot" downloadmacosrecovery

  mount "$DATA" "$MNT"
  cp -a "$WORK/recovery/com.apple.recovery.boot" "$MNT/"
  sync
  echo "==> installer partition contents:"; ls -1 "$MNT/com.apple.recovery.boot"
  umount "$MNT"
  rm -rf "$WORK"
fi

sync
cat <<'EOF'

Done. On the Latitude 5400:
  * BIOS: AHCI, Secure Boot OFF, USB boot ON, VT-d OFF if boot stalls.
  * The OpenCore picker shows the installer (or BaseSystem) and your macOS volumes.
  * Wi-Fi with the swapped BCM94352ZAE needs OCLP root patches after installing:
    docs/WIRELESS-BCM94352ZAE.md. Ethernet works out of the box.
EOF
