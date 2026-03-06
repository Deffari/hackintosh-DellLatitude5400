# Hackintosh for Dell Latitude 5400

---
~~**NOTE: I've got a real MacBook so this repository should not be considered up to date anymore. However, I keep my Latitude 5400 as well, with macOS installed, so if there is something really broken, let me know and I'll try my best.**~~

~~**2nd NOTE: That MacBook Pro was more unstable than my Hackintosh... But it was time to upgrade, so I got myself a Latitude 7430 (expect an EFI for this too :D). And I problably sell my 5400, so this might be the very last commit I do. Thank you all!**~~

~~**3rd NOTE: So that 7430 had Iris Xe graphics card -> No hackintoshing... But I sold it, and got a 5400 again. I am not into macOS anymore, but decided to update the repo anyhow. Enjoy!**~~

**4th NOTE: Switched to Framework, and it is again too new for hackintoshing :(**

---

*Based on **OpenCore 1.0.6**, of course.*

**WARNING: This repository now uses macOS 15 Sequoia, if you need info for Sonoma, Ventura, Monterey, or Big Sur; feel free to look at an older commit, or use tags.**

**Sequoia**: This EFI is configured for the **Broadcom BCM94352ZAE (DW1560-class)** Wi-Fi/Bluetooth card using `AirportBrcmFixup` (v2.2.0) and `BrcmPatchRAM3` + `BrcmFirmwareData` (v2.7.1). Intel Wi-Fi/BT kexts (`AirportItlwm`, `IntelBluetoothFirmware`) have been removed. If you still have the stock Intel 9560 card, see the [Troubleshooting](#no-wi-fi-or-bluetooth) section below. The OpenCanopy GUI picker is enabled with a 5-second auto-boot timer to macOS — you must populate `OC/Resources/` with assets from [OcBinaryData](https://github.com/acidanthera/OcBinaryData) for the graphical picker to appear (see [Troubleshooting](#boot-picker-shows-text-instead-of-gui)).

![About my Mac](.img/system.png)

## Specification

| | |
|-|-|
|**CPU**|Intel i5-8265U CPU @ 1.60GHz (Whiskey Lake)|
|**RAM**|24GB DDR4 2400MHz|
|**IGPU**|Intel UHD 620|
|**SSD**|Western Digital Black NVMe 500GB|
|**ETH**|Intel I217-LM|
|**WLAN+BT**|Broadcom BCM94352ZAE (DW1560-class) — native macOS Sequoia support|
|**WWAN**|Dell DW5809e (EM7305, 4G)|
|**Audio**|Realtek ALC236|
|**Ports**|USB-C (PD+DP-AltMode), 3xUSB3.0, HDMI, microSD, Multi-Jack, DC|

## Not working

- Dedicated brightness control keys (use Fn+S/Fn+B instead)
- HDMI coldplug (hotplug is OK)
- WWAN (worked before, but looks like now it is completly deprecated in macOS)
- *Hibernation (none of Hackintoshes can do that)*

## Working

- **Everything what is not in the Not working section :D**
- Bluetooth (LE, Handoff) via Broadcom BCM94352ZAE
- WLAN via Broadcom BCM94352ZAE (AirportBrcmFixup + brcmfx-country=#a boot-arg)
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

## Troubleshooting

### No Wi-Fi or Bluetooth

This EFI is configured for the **Broadcom BCM94352ZAE (DW1560-class)** card, not the stock Intel 9560 that ships with the Dell Latitude 5400. If you have the stock Intel card, Wi-Fi and Bluetooth will not work out of the box.

**Option A — Replace the card (recommended):** Swap the Intel 9560 for a Broadcom BCM94352ZAE (DW1560). This card has native macOS support and works with the kexts already included in this EFI (`AirportBrcmFixup`, `BrcmPatchRAM3`, `BrcmFirmwareData`, `BlueToolFixup`).

**Option B — Use Intel kexts instead:** If you want to keep the stock Intel 9560 card, you need to:
1. Download and add the following kexts to `OC/Kexts/`:
   - [AirportItlwm](https://github.com/OpenIntelWireless/itlwm/releases) (use the version matching your macOS — e.g. `AirportItlwm_Sequoia.kext`)
   - [IntelBluetoothFirmware](https://github.com/OpenIntelWireless/IntelBluetoothFirmware/releases) (includes `IntelBluetoothFirmware.kext` and `IntelBTPatcher.kext`)
2. In `config.plist`, under `Kernel > Add`:
   - **Disable** the Broadcom kexts: set `Enabled` to `false` for `AirportBrcmFixup.kext` (and its injector plug-ins), `BrcmFirmwareData.kext`, and `BrcmPatchRAM3.kext`
   - **Add and enable** entries for `AirportItlwm.kext`, `IntelBluetoothFirmware.kext`, and `IntelBTPatcher.kext`
   - Keep `BlueToolFixup.kext` enabled (it is needed for both Intel and Broadcom Bluetooth on macOS 12+)
3. In `NVRAM > Add > 7C436110-AB2A-4BBB-A880-FE41995C9F82`, you can remove `brcmfx-country=#a` from `boot-args` (it is Broadcom-specific)

### Boot picker shows text instead of GUI

The OpenCanopy GUI picker requires icon/font/label assets in the `OC/Resources/` directory. These binary assets are not included in this repository due to their size. To enable the graphical boot picker:

1. Download [OcBinaryData](https://github.com/acidanthera/OcBinaryData) from GitHub
2. Copy the **contents** of the `Resources` folder from OcBinaryData into `OC/Resources/`, so you have:
   ```
   OC/Resources/
   ├── Audio/
   ├── Font/
   ├── Image/
   └── Label/
   ```
3. Make sure `PickerMode` is set to `External` in `config.plist` (it already is by default in this EFI)

See [`OC/Resources/README.md`](OC/Resources/README.md) for more details.

## Contributing

Pull requests and suggestions are welcome!

**To share a config.plist or other files:**
- **GitHub Issue:** Open an [issue](../../issues) and drag-and-drop your file (rename `.plist` to `.plist.txt` or zip it first, since GitHub doesn't allow raw `.plist` uploads)
- **Pull Request:** Fork this repository, make your changes, and open a pull request — this is the best way to propose config changes
- **Gist:** Upload your file to [GitHub Gist](https://gist.github.com) and share the link in an issue

## Some random text

So I made this hackintosh basically just for fun, but it seems kinda stable, so I use it as my dialy driver. I've never had crashes with it.  

Regarding the not working stuff: with some time I managed to fix almost everything, so only two things are not working, but none of them is a deal-breaker:
 - The brightness control keys are not working, eventhough I added and configured the Brightness Control kext. I kept it, as with a version upgrade they might fix it.
 - HDMI coldplug: I have no idea why is it happing... But I use a USB-C docking station, so it's not a problem at all for me. And the port itself works, just need a re-plugging, so...

I would have a sentence about Intel Wifi+BT which the 5400 contains by default: When I started this project there was no such thing as Intel Wifi support at all. During the years kexts started to appear, and now I have seen promising results. That's why I digged my stock card up, placed it back, and made my EFI compatible with it! So it will work with stock WLAN card. Eventhough I would still recommend getting a natively supported one, first because the Intel card was not so stable (usuable, but not smooth (for example slow network scanning)), secondly as they did with Ventura, Apple can rewrite the whole BT/WLAN with any upgrade. There is nothing better than natively supported hardware, even in this wild west... :)
