#!/usr/bin/env bash
# make-usb-macos.sh - build the Hackintosh USB flash drive on macOS.
#
# Two things always happen:
#   1. BOOT/ and OC/ from this repository are copied to the EFI system partition (ESP)
#      of the USB drive - that is what makes the stick boot OpenCore.
#   2. Optionally a macOS installer is written with createinstallmedia, so the same
#      stick can also install macOS. Without --installer you get a boot/recovery/fix stick.
#
# Usage:
#   sudo ./scripts/make-usb-macos.sh --disk /dev/disk4
#   sudo ./scripts/make-usb-macos.sh --disk /dev/disk4 --installer "/Applications/Install macOS Sequoia.app"
#
# WARNING: everything on the target disk is erased. Double-check the disk number with
#          `diskutil list` first; the script refuses internal disks and requires --yes.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DISK=""
INSTALLER=""
CONFIRM="no"

usage() {
  sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --disk) DISK="${2:-}"; shift 2 ;;
    --installer) INSTALLER="${2:-}"; shift 2 ;;
    --yes) CONFIRM="yes"; shift ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done

[[ "$(uname -s)" == "Darwin" ]] || { echo "this script must run on macOS" >&2; exit 1; }
[[ -n "$DISK" ]] || { echo "--disk is required (e.g. --disk /dev/disk4)" >&2; usage; }
[[ "$DISK" =~ ^/dev/disk[0-9]+$ ]] || { echo "unexpected disk device: $DISK" >&2; exit 1; }
[[ -d "$ROOT/OC" && -d "$ROOT/BOOT" ]] || { echo "run this from the repository (OC/ and BOOT/ missing)" >&2; exit 1; }
command -v diskutil >/dev/null || { echo "diskutil not found" >&2; exit 1; }

# --- safety: only removable media -------------------------------------------------
INTERNAL="$(diskutil info -plist "$DISK" | /usr/libexec/PlistBuddy -c "Print :Internal" /dev/stdin 2>/dev/null || echo "true")"
REMOVABLE="$(diskutil info -plist "$DISK" | /usr/libexec/PlistBuddy -c "Print :Removable" /dev/stdin 2>/dev/null || echo "false")"
if [[ "$INTERNAL" == "true" ]]; then
  echo "refusing to touch $DISK: it is reported as an internal disk" >&2
  exit 1
fi
echo "target : $DISK (removable=$REMOVABLE, internal=$INTERNAL)"
if [[ "$CONFIRM" != "yes" ]]; then
  echo "re-run with --yes to confirm that EVERYTHING on $DISK will be erased" >&2
  exit 1
fi

# --- step 1: write the installer, or just prepare a data volume --------------------
if [[ -n "$INSTALLER" ]]; then
  [[ -x "$INSTALLER/Contents/Resources/createinstallmedia" ]] || {
    echo "createinstallmedia not found in $INSTALLER" >&2; exit 1; }
  VOLUME_NAME="$(basename "$INSTALLER" .app)"
  echo "==> writing installer with createinstallmedia (this takes a while)"
  diskutil eraseDisk JHFS+ "$VOLUME_NAME" GPT "$DISK" >/dev/null
  "$INSTALLER/Contents/Resources/createinstallmedia" --volume "/Volumes/$VOLUME_NAME" --nointeraction
else
  echo "==> creating a plain boot/recovery stick"
  diskutil eraseDisk JHFS+ "OPENCORE-USB" GPT "$DISK" >/dev/null
fi

# --- step 2: copy the EFI folder to the ESP ----------------------------------------
ESP_DEV="$(diskutil list "$DISK" | awk '/EFI EFI/ {print $NF; exit}')"
[[ -n "$ESP_DEV" ]] || { echo "could not find the EFI system partition on $DISK" >&2; exit 1; }
ESP_MOUNT="$(diskutil mount "$ESP_DEV" | sed -n 's/^.*mounted on \(.*\)$/\1/p')"
if [[ -z "$ESP_MOUNT" ]]; then
  ESP_MOUNT="/Volumes/EFI"
  diskutil mount "$ESP_DEV" >/dev/null
fi
[[ -d "$ESP_MOUNT" ]] || { echo "ESP $ESP_DEV did not mount" >&2; exit 1; }

echo "==> copying EFI to $ESP_DEV ($ESP_MOUNT)"
rm -rf "$ESP_MOUNT/EFI"
mkdir -p "$ESP_MOUNT/EFI"
ditto "$ROOT/BOOT" "$ESP_MOUNT/EFI/BOOT"
ditto "$ROOT/OC"   "$ESP_MOUNT/EFI/OC"
sync
echo "==> EFI written:"; ls -1 "$ESP_MOUNT/EFI"
diskutil unmount "$ESP_DEV" >/dev/null

cat <<'EOF'

Done. Next steps on the Latitude 5400:
  1. BIOS: SATA = AHCI, Secure Boot = OFF, "Enable USB Boot Support" = ON,
     Thunderbolt boot = OFF, and disable VT-d if you see boot stalls.
  2. Boot the stick (F12 boot menu) -> OpenCore picker -> "Install macOS ..." or your
     installed macOS volume.
  3. Wi-Fi on the swapped BCM94352ZAE card needs OCLP root patches after the install:
     see docs/WIRELESS-BCM94352ZAE.md. Ethernet works out of the box.
  4. Recovery/fixing: pick "macOS Base System" in the picker; ResetNvramEntry and
     ToggleSipEntry are available as OpenCore tools.
EOF
