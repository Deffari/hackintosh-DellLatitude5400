# Hackintosh for Dell Latitude 5400

---
~~**NOTE: I've got a real MacBook so this repository should not be considered up to date anymore. However, I keep my Latitude 5400 as well, with macOS installed, so if there is something really broken, let me know and I'll try my best.**~~

~~**2nd NOTE: That MacBook Pro was more unstable than my Hackintosh... But it was time to upgrade, so I got myself a Latitude 7430 (expect an EFI for this too :D). And I problably sell my 5400, so this might be the very last commit I do. Thank you all!**~~

~~**3rd NOTE: So that 7430 had Iris Xe graphics card -> No hackintoshing... But I sold it, and got a 5400 again. I am not into macOS anymore, but decided to update the repo anyhow. Enjoy!**~~

**4th NOTE: Switched to Framework, and it is again too new for hackintoshing :(**

---

*Based on **OpenCore 1.0.8**, of course.*

**WARNING: This repository now uses macOS 15 Sequoia, if you need info for Sonoma, Ventura, Monterey, or Big Sur; feel free to look at an older commit, or use tags.**

**Sequoia / Tahoe**: This EFI is configured for the **Broadcom BCM94352ZAE (DW1560-class)** Wi-Fi/Bluetooth card physically installed in this laptop. Wi-Fi with this chip was removed by Apple in macOS 14, so on Sequoia/Tahoe it needs **OpenCore Legacy Patcher root patches** on top of the EFI. The EFI ships what that requires: `IOSkywalkFamily` + `IO80211FamilyLegacy` + `AirPortBrcmNIC` (bounded to Darwin 23-24) and `AirPortBrcmNIC-Tahoe` (Darwin 25+), `AMFIPass`, `ECM-Override`, `com.apple.iokit.IOSkywalkFamily` blocked in `Kernel/Block`, `csr-active-config = 03080000`, `SecureBootModel = Disabled` and `-brcmfxbeta` in `boot-args`. Bluetooth works from the EFI alone (`BrcmPatchRAM3` 2.7.2 + `BrcmFirmwareData` + `BlueToolFixup`, plus the mandatory `bluetoothInternalControllerInfo` / `bluetoothExternalDongleFailed` NVRAM values). The OpenCanopy GUI picker is enabled with a 4-second auto-boot timer to macOS and a complete `OC/Resources`.

Read [docs/WIRELESS-BCM94352ZAE.md](docs/WIRELESS-BCM94352ZAE.md) before touching anything wireless-related, [docs/UPGRADE-1.0.8.md](docs/UPGRADE-1.0.8.md) for the upgrade/verification report, and [docs/USB-CREATION.md](docs/USB-CREATION.md) for building the boot/install stick. `components.lock` pins every component version, `scripts/verify-efi.py` verifies the whole tree, and `scripts/check-updates.py` reports what is newer upstream.

![About my Mac](.img/system.png)

## Specification

| | |
|-|-|
|**CPU**|Intel i5-8265U CPU @ 1.60GHz (Whiskey Lake)|
|**RAM**|24GB DDR4 2400MHz|
|**IGPU**|Intel UHD 620|
|**SSD**|Western Digital Black NVMe 500GB|
|**ETH**|Intel I217-LM|
|**WLAN+BT**|Broadcom BCM94352ZAE (DW1560-class) — Wi-Fi needs OCLP root patches on macOS 14+, Bluetooth works from the EFI|
|**WWAN**|Dell DW5809e (EM7305, 4G)|
|**Audio**|Realtek ALC236|
|**Ports**|USB-C (PD+DP-AltMode), 3xUSB3.0, HDMI, microSD, Multi-Jack, DC|

## Not working

- Dedicated brightness control keys (use Fn+S/Fn+B instead)
- HDMI coldplug (hotplug is OK)
- WWAN (worked before, but looks like now it is completly deprecated in macOS)
- *Hibernation (none of Hackintoshes can do that)*
- **Wi-Fi on macOS 14+ without OCLP root patches** (Apple removed `AirPortBrcmNIC`; see docs/WIRELESS-BCM94352ZAE.md)

## Working

- **Everything what is not in the Not working section :D**
- Bluetooth (LE, Handoff) via Broadcom BCM94352ZAE (BrcmPatchRAM3 2.7.2 + BlueToolFixup)
- WLAN via Broadcom BCM94352ZAE (AirportBrcmFixup + `brcmfx-country=#a`, plus OCLP root patches on macOS 14+)
- Ethernet
- HDMI, DisplayPort Alt Mode (all with sound, but no volume adjustment)
- USB-C (I'm using it with a docking station all the time)
- USB ports mapped, working after sleep
- TrackPad with gestures (visible as Magic Trackpad 2)
- Audio, with speaker and microphone support
- QE/CI
- Sleep
- MicroSD card reader
- TouchPad buttons
- TrackStick
- Multi-Jack (both cold- and hotplug)

## Repository layout

| Path | Contents |
|-|-|
| `BOOT/BOOTx64.efi` | OpenCore bootstrap (copied to the USB's `EFI/BOOT/`) |
| `OC/OpenCore.efi`, `OC/Drivers`, `OC/Tools` | OpenCore 1.0.8 core, 33 UEFI drivers, 15 tools |
| `OC/ACPI` | 10 SSDTs (AWAC, PLUG, PMC, PNLF-CFL, GPI0, GPRW, UPRW, HPET, SBUS-MCHC, XOSI) |
| `OC/Kexts` | 33 kexts (see `components.lock`) |
| `OC/Resources` | OpenCanopy fonts, icons, labels, audio assist (required by `PickerMode = External`) |
| `OC/config.plist` | validated by `ocvalidate` from OpenCore 1.0.8 |
| `components.lock` | pinned versions, bundle ids, upstream sources and core hashes |
| `scripts/` | verification, update-checking, packaging and USB creation tools |
| `docs/` | upgrade report, wireless deep-dive, USB guide |

## Verifying and upgrading

```bash
python3 scripts/verify-efi.py --fetch-ocvalidate   # 11 checks, all green expected
python3 scripts/check-updates.py                   # what is newer upstream than components.lock
./scripts/pack-efi.sh                              # dist/EFI-OpenCore-<version>.zip
```

`verify-efi.py` checks that every `config.plist` reference exists, that no orphan kexts or drivers
are shipped, that the **kext dependency graph resolves inside the injected set** (so the whole boot
compilation still works together after an upgrade), that Lilu is injected before its plugins, that
no duplicate bundle identifiers load for the same macOS range, that OpenCanopy resources exist for
`PickerMode = External`, that the BCM94352ZAE requirements are met, and that the tree matches
`components.lock` and the pinned OpenCore hashes. After any component bump, update
`components.lock`, run `verify-efi.py --write-hashes` if core binaries changed, then re-verify.

## Making the USB stick

```bash
# macOS
sudo ./scripts/make-usb-macos.sh --disk /dev/disk4 --yes      --installer "/Applications/Install macOS Sequoia.app"
# Linux
sudo ./scripts/make-usb-linux.sh --disk /dev/sdb --recovery 15
```

See [docs/USB-CREATION.md](docs/USB-CREATION.md) for the manual equivalents, BIOS settings,
booting/fixing/installing workflows and troubleshooting.

## Some random text

So I made this hackintosh basically just for fun, but it seems kinda stable, so I use it as my dialy driver. I've never had crashes with it.  

Regarding the not working stuff: with some time I managed to fix almost everything, so only two things are not working, but none of them is a deal-breaker:
 - The brightness control keys are not working, eventhough I added and configured the Brightness Control kext. I kept it, as with a version upgrade they might fix it.
 - HDMI coldplug: I have no idea why is it happing... But I use a USB-C docking station, so it's not a problem at all for me. And the port itself works, just need a re-plugging, so...

I would have a sentence about Intel Wifi+BT which the 5400 contains by default: When I started this project there was no such thing as Intel Wifi support at all. During the years kexts started to appear, and now I have seen promising results. That's why I digged my stock card up, placed it back, and made my EFI compatible with it! So it will work with stock WLAN card. Eventhough I would still recommend getting a natively supported one, first because the Intel card was not so stable (usuable, but not smooth (for example slow network scanning)), secondly as they did with Ventura, Apple can rewrite the whole BT/WLAN with any upgrade. There is nothing better than natively supported hardware, even in this wild west... :)

Pull requests or suggestions are welcome! :)
