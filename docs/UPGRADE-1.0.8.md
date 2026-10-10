# EFI upgrade & verification report — OpenCore 1.0.6 → 1.0.8

Date: 2026-10-10 · Machine: Dell Latitude 5400 (i5-8265U, UHD 620) · Card: **Broadcom BCM94352ZAE (DW1560-class)**

This is the "inspect and verify current status, then upgrade" record for this repository.
Everything below was checked against upstream sources, not assumed.

## 1. Version inventory (before → after)

| Component | Before | After | Upstream |
|-|-|-|-|
| OpenCore | 1.0.6 (2025-11-03) | **1.0.8 (2026-09-27)** | acidanthera/OpenCorePkg |
| BOOTx64.efi / OpenCore.efi | 1.0.6 | **1.0.8** | same release, byte-identical |
| OC/Drivers | 33 files @ 1.0.6 | **33 files @ 1.0.8** | same release |
| OC/Tools | 15 files @ 1.0.6 | **15 files @ 1.0.8** | same release |
| OC/Resources (OpenCanopy) | **missing entirely** | **Font/Image/Label/Audio added** | acidanthera/OcBinaryData |
| Lilu | 1.7.1 | **1.7.2** | acidanthera/Lilu |
| VirtualSMC (+ SMCBatteryManager, SMCDellSensors, SMCProcessor, SMCSuperIO) | 1.3.7 | **1.3.8** | acidanthera/VirtualSMC |
| WhateverGreen | 1.7.0 | **1.7.1** | acidanthera/WhateverGreen |
| AppleALC | 1.9.6 | **1.9.8** | acidanthera/AppleALC |
| AirportBrcmFixup | 2.2.0 | **2.2.1** | acidanthera/AirportBrcmFixup |
| BrcmPatchRAM3 / BrcmFirmwareData / BlueToolFixup | 2.7.1 | **2.7.2** | acidanthera/BrcmPatchRAM |
| IOSkywalkFamily / IO80211FamilyLegacy (+AirPortBrcmNIC) / AirPortBrcmNIC-Tahoe / AMFIPass / ECM-Override | — | **1.2.0 / 1.0.0 / 1.0.0 / 1.4.1 / 1.0.0** | dortania/OpenCore-Legacy-Patcher payloads |
| CPUFriend 1.3.0, IntelMausi 1.0.8, NVMeFix 1.1.3, RestrictEvents 1.1.6, BrightnessKeys 1.0.3, VoodooPS2 2.3.7, VoodooI2C 2.9.1, RealtekCardReader 0.9.7 / Friend 1.0.4, NoTouchID 1.0.4, AlpsHID 1.0.0d1, USBPorts, XHCI-unsupported 0.9.2, vkgLegacySierraQMI | unchanged | already current |

The full machine-readable list (bundle ids, versions, sources, hashes) is in
[`components.lock`](../components.lock); `scripts/check-updates.py` re-checks it against
upstream at any time.

## 2. What was actually broken (findings)

1. **OpenCore 1.0.8 config schema.** 1.0.8 added `UEFI/Drivers/HideVerbose`. The shipped
   config had 33 driver entries without it, so the *new* `ocvalidate` reported
   **33 errors** — the old 1.0.6 validator reported none. Fixed; 1.0.8 `ocvalidate` now
   reports *"No issues found"*.
2. **OpenCanopy had no resources.** `Misc/Boot/PickerMode = External` with an **empty
   `OC/Resources`** (the folder did not exist at all). OpenCanopy cannot draw the GUI
   picker without `Resources/Font`, `Resources/Image` and `Resources/Label`; it falls back
   to the text picker/errors out. Added the complete OcBinaryData resource set (audio assist
   included, so `PickerAudioAssist` also works if enabled).
3. **The Wi-Fi claim in the README was wrong.** It said the BCM94352ZAE has *"native
   macOS Sequoia support"*. It does not: Apple removed `AirPortBrcmNIC` in macOS 14+.
   Upstream AirportBrcmFixup documents `[14+] Use with OCLP`, and OCLP re-enables
   third-party Broadcom chipsets (device id `14e4:43b1` = BCM4352 is explicitly on that
   list) through **root patches**, which additionally need:
   `IOSkywalkFamily.kext`, `IO80211FamilyLegacy.kext` (+ `AirPortBrcmNIC.kext`),
   `AMFIPass.kext`, `com.apple.iokit.IOSkywalkFamily` blocked in `Kernel/Block`,
   `csr-active-config = 03080000`, `SecureBootModel = Disabled` and `-brcmfxbeta`.
   **None of that was in the EFI**, so Wi-Fi could not work on Sequoia no matter what the
   card was. All of it is now in place, plus `AirPortBrcmNIC-Tahoe.kext` for macOS 26 and
   `ECM-Override.kext` so USB-C dock Ethernet survives the IOSkywalk downgrade.
4. **Bluetooth was missing its mandatory NVRAM variables.** BrcmPatchRAM 2.7.x requires
   `bluetoothInternalControllerInfo` (12 zero bytes) and `bluetoothExternalDongleFailed`
   (`00`) in NVRAM; they were absent, which is the classic "BT kext loads but nothing
   works" state. Added, including the matching `NVRAM/Delete` entries so stale values are
   not inherited. `-btlfxboardid` was added as well (documented for macOS 14+ with
   BrcmPatchRAM >= 2.7.0), and BrcmPatchRAM 2.7.2 brings the macOS 26 `bluetoothd` patches.
5. **Everything was one to three releases behind** (OpenCore two, Lilu/AppleALC/
   WhateverGreen/AirportBrcmFixup one). All bumped to the latest stable releases.
6. Cosmetic: `Booter/Quirks/ClearTaskSwitchBit` was appended out of alphabetical order by
   the previous commit; the file is now written in canonical sorted order like the rest.


## 3. Verification evidence (reproducible)

```
$ /tmp/ocvalidate108 OC/config.plist          # ocvalidate taken from OpenCore 1.0.8
Completed validating OC/config.plist in 2 ms. No issues found.

$ python3 scripts/verify-efi.py --ocvalidate /tmp/ocvalidate108
[OK  ] every config.plist reference resolves to a file on disk
[OK  ] no orphan kexts in OC/Kexts
[OK  ] no orphan drivers in OC/Drivers
[OK  ] every injected kext dependency is satisfied by the injected set
[OK  ] Lilu is injected before every Lilu plugin
[OK  ] no conflicting duplicate kext identifiers (range-bounded duplicates are fine)
[OK  ] OpenCanopy resources present for PickerMode=External
[OK  ] Broadcom BCM94352ZAE Wi-Fi/Bluetooth requirements are all met
[OK  ] all 33 kexts match components.lock (OpenCore 1.0.8)
[OK  ] OpenCore core binaries match the pinned 1.0.8 release hashes
[OK  ] ocvalidate: ocvalidate108 reports no issues with config.plist
11 checks: 11 ok, 0 warnings, 0 failures
```

* **"Does the whole boot compilation still work together?"** is answered by the kext
  dependency-graph check: every `OSBundleLibraries` entry of every injected kext is
  resolved by another injected kext at a sufficient version (Lilu plugins, VirtualSMC SMC
  plugins, BrcmFirmwareStore for BrcmPatchRAM3, VoodooI2CServices/VoodooGPIO/VoodooInput
  for VoodooI2C, VoodooInput for AlpsHID, CPUFriend for CPUFriendDataProvider), and Lilu is
  injected before every plugin. The check is not vacuous: deliberately disabling
  `AirPortBrcmNIC_Injector`, deleting the `IOSkywalkFamily` block and dropping
  `-brcmfxbeta` produces exactly those three failures.
* `OC/OpenCore.efi` and `BOOT/BOOTx64.efi` hashes match the official
  `OpenCore-1.0.8-RELEASE.zip` byte-for-byte (recorded in `components.lock`).
* The duplicate-identifier check is what makes the macOS 14/15 + macOS 26 Wi-Fi stack safe:
  `AirPortBrcmNIC.kext` (inside `IO80211FamilyLegacy`) is bounded to Darwin 23–24 and
  `AirPortBrcmNIC-Tahoe.kext` starts at Darwin 25, so the two copies of
  `com.apple.driver.AirPort.BrcmNIC` never load at the same time.

## 4. What still has to be confirmed on real hardware

This sandbox can validate files, plists and the compatibility matrix — it cannot boot the
laptop. After flashing the stick, please confirm on the machine:

- [ ] OpenCore picker renders with icons/labels (proves `OC/Resources` is on the ESP).
- [ ] macOS 15 Sequoia boots with the new OpenCore/kexts; sleep, audio, trackpad, USB-C dock.
- [ ] Bluetooth: card discovered, `bluetoothd` healthy, AirDrop/Handoff work.
- [ ] Wi-Fi: only after OCLP root patches (see `docs/WIRELESS-BCM94352ZAE.md`).
- [ ] Installer boot (`Install macOS …`) and Recovery (`macOS Base System`) both reach the GUI.
- [ ] Boot-args are what you expect (table in `docs/USB-CREATION.md`).

If anything regresses, `git revert` of the two upgrade commits returns the tree to the
1.0.6 baseline, and `scripts/verify-efi.py` will tell you immediately whether the tree is
self-consistent after any hand edit.

