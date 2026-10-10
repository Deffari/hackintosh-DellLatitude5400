# Building and using the USB flash drive

The stick has two jobs, and this repository supports both from the same EFI folder:

* **Boot / fix** — always: `BOOT/` + `OC/` on the EFI system partition (ESP) boot OpenCore,
  which gives you the picker, the macOS Recovery ("macOS Base System") environment, the
  `ResetNvramEntry` / `ToggleSipEntry` / `OpenShell` tools, and your installed macOS.
* **Install** — optionally the same stick carries a macOS installer (or a recovery
  BaseSystem image) so you can install macOS from scratch.

Before flashing anything, verify the tree you are about to copy:

```bash
python3 scripts/verify-efi.py --fetch-ocvalidate   # 11/11 checks expected
./scripts/pack-efi.sh                              # optional: dist/EFI-OpenCore-<ver>.zip
```

## 1. Prerequisites

* USB flash drive: 16 GB+ for a full installer, 2 GB+ is enough for a recovery/boot stick.
  USB 2.0 sticks are actually the safest for the picker/firmware.
* BIOS (F2 on the Latitude 5400): SATA **AHCI**, Secure Boot **off**, "Enable USB Boot
  Support" **on**, Thunderbolt boot **off**, and VT-d off if the boot stalls.
* The ESP must be **FAT32** and contain `EFI/BOOT/BOOTx64.efi` plus `EFI/OC/…`. The
  `.contentFlavour` / `.contentVisibility` files from the release are included so OpenCore
  hides its own ESP entry from the picker.

## 2. macOS: build the stick (recommended)

```bash
diskutil list                                    # find the USB, e.g. /dev/disk4
# boot/fix stick only:
sudo ./scripts/make-usb-macos.sh --disk /dev/disk4 --yes
# full installer stick (erases the stick, takes a while):
sudo ./scripts/make-usb-macos.sh --disk /dev/disk4 --yes \
     --installer "/Applications/Install macOS Sequoia.app"
```

The script refuses internal disks, requires `--yes`, writes the installer with
`createinstallmedia`, then copies `BOOT/` + `OC/` into the ESP with `ditto`.

Manual equivalent if you prefer doing it by hand:

```bash
sudo diskutil eraseDisk JHFS+ MACUSB GPT /dev/disk4
sudo "/Applications/Install macOS Sequoia.app/Contents/Resources/createinstallmedia" \
     --volume /Volumes/MACUSB --nointeraction
diskutil mount disk4s1                # the ESP
mkdir -p /Volumes/EFI/EFI && cp -R BOOT OC /Volumes/EFI/EFI/
diskutil unmount disk4s1
```

## 3. Linux: build the stick

```bash
lsblk                                            # find the USB, e.g. /dev/sdb
sudo ./scripts/make-usb-linux.sh --disk /dev/sdb                       # boot/fix stick
sudo ./scripts/make-usb-linux.sh --disk /dev/sdb --recovery 15         # + Sequoia BaseSystem
sudo ./scripts/make-usb-linux.sh --disk /dev/sdb --recovery 26         # + Tahoe BaseSystem
```

It creates a 200 MB FAT32 ESP with the EFI folder and a second FAT32 partition. With
`--recovery` it fetches `BaseSystem.dmg` + `BaseSystem.chunklist` through OpenCore's
`macrecovery` utility into `com.apple.recovery.boot/`, which OpenCore boots as a macOS
installer/recovery environment (the machine needs network access to download the ~700 MB
installer payload when it starts installing).

Manual equivalent:

```bash
sudo sgdisk --zap-all /dev/sdb
sudo sgdisk -n 1:2048:+200M -t 1:ef00 -c 1:EFI /dev/sdb
sudo mkfs.vfat -F32 -n EFI /dev/sdb1
sudo mount /dev/sdb1 /mnt && sudo mkdir -p /mnt/EFI
sudo cp -a BOOT OC /mnt/EFI/ && sync && sudo umount /mnt
```

## 4. Windows

Use OpenCore's `macrecovery` (bundled in every OpenCore release under
`Utilities/macrecovery`) to download the BaseSystem, then copy `BOOT/` + `OC/` and
`com.apple.recovery.boot/` to a FAT32 stick (Rufus in "GPT / UEFI / FAT32" mode works, or
just format the stick as FAT32 and copy the folders). The ESP requirement is satisfied by a
plain FAT32 partition on a GPT disk.

## 5. Booting

1. Insert the stick, press **F12** at the Dell logo, pick the USB device.
2. The OpenCanopy picker appears (icons/labels — if you only get a text menu, the
   `OC/Resources` folder did not make it onto the ESP).
3. Entries: `Install macOS <version>` / `macOS Base System` (recovery), your installed
   macOS volumes, `Reset NVRAM`, `UEFI Shell`, `OpenShell`, and firmware settings.
4. Tools worth knowing: **ResetNvramEntry** (after changing NVRAM keys or switching macOS
   versions), **ToggleSipEntry** (temporarily toggles SIP), **CsrUtil** (print SIP state),
   **CleanNvram**, **OpenShell** (manual EFI poking), **ControlMsrE2** (CFG-lock check).
5. Timeout is 4 s (configured) and the default boot entry is macOS.

## 6. Installing macOS with this stick

1. Boot the stick → pick the installer/BaseSystem entry.
2. `Disk Utility` → erase the internal NVMe as **APFS** (GUID map).
3. Install macOS, letting it reboot through the OpenCore picker each time
   ("macOS Installer" entries appear automatically).
4. After the install finishes, Ethernet works immediately (Intel I217-LM via `IntelMausi`).
5. Apply the Wi-Fi root patches — see `docs/WIRELESS-BCM94352ZAE.md` (the swapped Broadcom
   card needs OCLP on macOS 14+).
6. Optionally re-enable `SecureBootModel` later *only* if you decide to give up the
   Broadcom Wi-Fi patch.

## 7. Fixing / recovery workflows

| Problem | What to do with the stick |
|-|-|
| macOS won't boot after an update | Boot the picker, choose a snapshot/recovery entry, or boot with `-v` and read the last lines |
| Broken NVRAM / wrong boot-args stuck | `Reset Nvram` entry, or `CleanNvram` tool |
| SIP got re-enabled and patched Wi-Fi stopped | `CsrUtil` tool to check, `ToggleSipEntry` to toggle, then re-apply OCLP root patches |
| Wrong default boot volume | Pick the volume once, then set it as default in System Settings, or use `Ctrl`+Enter in the picker (`AllowSetDefault` is on) |
| Need to edit the EFI from the stick | Boot `OpenShell` or mount the ESP on another Mac/Linux box |
| Kext/EFI update | Edit the repo, run `scripts/verify-efi.py`, then re-copy `BOOT`/`OC` to the ESP |

## 8. Boot-args reference (current values)

`keepsyms=1 -wegbeta -igfxblt revpatch=sbvmm brcmfx-country=#a -brcmfxbeta -btlfxboardid ipc_control_port_options=0`

| Argument | Why |
|-|-|
| `keepsyms=1` | readable kernel panic symbols |
| `-wegbeta` | allows WhateverGreen on beta macOS builds |
| `-igfxblt` | WhateverGreen: BLT-only backlight path (this panel's brightness fix) |
| `revpatch=sbvmm` | RestrictEvents: VMM SB model spoof (software-update/asset fixes on macOS 15+) |
| `brcmfx-country=#a` | AirportBrcmFixup: world regulatory domain for the BCM94352ZAE |
| `-brcmfxbeta` | AirportBrcmFixup: required to patch on macOS 14+ |
| `-btlfxboardid` | BlueToolFixup: board-id workaround for Broadcom BT on macOS 14+ |
| `ipc_control_port_options=0` | workaround for Electron apps with SIP lowered |

Temporary debug runs can be done by editing `boot-args` in the picker's
`Reset NVRAM`-adjacent workflow or by adding `-v` (verbose), `-brcmfxdbg`, `-liludbgall`.

## 9. Troubleshooting the stick itself

| Symptom | Cause / fix |
|-|-|
| Text-only picker, no icons | `OC/Resources` missing on the ESP (Font/Image/Label) |
| "OC: Failed to load …" for a driver/kext | ESP not FAT32, files copied with wrong case, or the file was not copied at all — re-run `scripts/pack-efi.sh` and re-copy |
| No OpenCore entry at all in the firmware boot menu | BIOS USB boot disabled, or `EFI/BOOT/BOOTx64.efi` not on the ESP |
| Picker appears but no macOS volumes | `Misc/Security/ScanPolicy` is 0 (all devices scanned) so this is usually a stale NVRAM/`Reset Nvram` case, or an unmounted FileVault volume |
| Kernel panic right after "root patched" install | SIP/`SecureBootModel` reverted — see the table in `docs/WIRELESS-BCM94352ZAE.md` §5 |
| Wi-Fi works but only until reboot | the injected `IOSkywalkFamily`/`AirPortBrcmNIC` pair was removed or the `Kernel/Block` entry was dropped; `scripts/verify-efi.py` catches this |

