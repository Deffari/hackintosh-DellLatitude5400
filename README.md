# Hackintosh for Dell Latitude 5400

---
~~**NOTE: I've got a real MacBook so this repository should not be considered up to date anymore. However, I keep my Latitude 5400 as well, with macOS installed, so if there is something really broken, let me know and I'll try my best.**~~

~~**2nd NOTE: That MacBook Pro was more unstable than my Hackintosh... But it was time to upgrade, so I got myself a Latitude 7430 (expect an EFI for this too :D). And I problably sell my 5400, so this might be the very last commit I do. Thank you all!**~~

~~**3rd NOTE: So that 7430 had Iris Xe graphics card -> No hackintoshing... But I sold it, and got a 5400 again. I am not into macOS anymore, but decided to update the repo anyhow. Enjoy!**~~

**4th NOTE: Switched to Framework, and it is again too new for hackintoshing :(**

---

*Based on **OpenCore 1.0.6**, of course.*

**WARNING: This repository now uses macOS 15 Sequoia, if you need info for Sonoma, Ventura, Monterey, or Big Sur; feel free to look at an older commit, or use tags.**

**Sequoia**: This EFI is configured for the **Broadcom BCM94352ZAE (DW1560-class)** Wi-Fi/Bluetooth card using `AirportBrcmFixup` (v2.2.0) and `BrcmPatchRAM3` + `BrcmFirmwareData` (v2.7.1). Intel Wi-Fi/BT kexts (`AirportItlwm`, `IntelBluetoothFirmware`) have been removed. If you still have the stock Intel 9560 card, replace it with BCM94352ZAE for full native support. The OpenCanopy GUI picker is enabled with a 5-second auto-boot timer to macOS.

## Getting Started (Start Your Own Build)

Want to use this EFI as the foundation for your own Dell Latitude 5400 hackintosh? Follow these steps:

### 1. Fork or clone the base repository

This EFI is derived from **[msbence's OpenCore Sequoia EFI](https://github.com/msbence/hackintosh)**. To start fresh from the same base:

1. Go to the [msbence hackintosh repository](https://github.com/msbence/hackintosh) on GitHub
2. Click **Fork** (top-right) to copy it to your own GitHub account, **or** click **Releases** to download the latest pre-built EFI zip directly
3. Alternatively, fork **this** repository if you want to start from the already-customised Dell Latitude 5400 EFI

### 2. Download and place the EFI

1. Download the latest EFI release zip from the [Releases](../../releases) page of whichever repo you forked
2. Extract it and copy the `EFI/` folder to the root of your USB flash drive (formatted as FAT32)
   - The result should be `USB:/EFI/BOOT/BOOTx64.efi` and `USB:/EFI/OC/config.plist`

### 3. Choose a config.plist for your hardware

Two ready-to-use config files are provided in the [`configs/`](configs/) folder:

| Config | Wi-Fi Card | Wi-Fi | Bluetooth | Notes |
|---|---|---|---|---|
| `configs/broadcom-wifi-bt/config.plist` | BCM94352ZAE (DW1560) | ✅ Working | ✅ Working | Main EFI config (also at `OC/config.plist`) |
| `configs/intel-wifi-base/config.plist` | Intel Wireless-AC 9560 (stock) | ✅ Working | ⚠️ Needs setup | Use this if you kept the stock Intel card — see [Bluetooth setup notes](configs/intel-wifi-base/README.md) |

Copy the config you need to `EFI/OC/config.plist` on your USB drive.

### 4. Generate your own SMBIOS

> **This step is mandatory.** Never use someone else's serial number.

1. Download [GenSMBIOS](https://github.com/corpnewt/GenSMBIOS) and run it
2. Choose model **MacBookPro15,4** (already set in the provided config files)
3. Paste the generated `SystemSerialNumber`, `MLB`, `SystemUUID`, and `ROM` into your `config.plist` under `PlatformInfo > Generic`
4. Use [ProperTree](https://github.com/corpnewt/ProperTree) or any plist editor to make the edit

### 5. Boot and finish macOS installation

1. Boot your Latitude 5400 from the USB (press F12 at the Dell splash screen to get the boot menu)
2. Select your USB in OpenCore, then choose **Install macOS Sequoia**
3. After installation, [mount your EFI partition](https://dortania.github.io/OpenCore-Post-Install/universal/oc2hdd.html) and copy the EFI folder there so you can boot without the USB

### Adding your own config.plist to this repository

If you have a working (or almost-working) `config.plist` that you want to save and share:

1. Create a folder under `configs/` that describes your hardware variant (e.g. `configs/intel-wifi-base/`)
2. Place your `config.plist` in that folder
3. Add a short `README.md` next to it describing what works, what doesn't, and any required kexts
4. Open a Pull Request — contributions are very welcome!

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

## Some random text

So I made this hackintosh basically just for fun, but it seems kinda stable, so I use it as my dialy driver. I've never had crashes with it.  

Regarding the not working stuff: with some time I managed to fix almost everything, so only two things are not working, but none of them is a deal-breaker:
 - The brightness control keys are not working, eventhough I added and configured the Brightness Control kext. I kept it, as with a version upgrade they might fix it.
 - HDMI coldplug: I have no idea why is it happing... But I use a USB-C docking station, so it's not a problem at all for me. And the port itself works, just need a re-plugging, so...

I would have a sentence about Intel Wifi+BT which the 5400 contains by default: When I started this project there was no such thing as Intel Wifi support at all. During the years kexts started to appear, and now I have seen promising results. That's why I digged my stock card up, placed it back, and made my EFI compatible with it! So it will work with stock WLAN card. Eventhough I would still recommend getting a natively supported one, first because the Intel card was not so stable (usuable, but not smooth (for example slow network scanning)), secondly as they did with Ventura, Apple can rewrite the whole BT/WLAN with any upgrade. There is nothing better than natively supported hardware, even in this wild west... :)

Pull requests or suggestions are welcome! :)
