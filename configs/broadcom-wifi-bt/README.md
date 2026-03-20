# Config: Broadcom BCM94352ZAE (DW1560-class)

This is the **main / recommended** config for the Dell Latitude 5400 with the
Broadcom BCM94352ZAE (a.k.a. DW1560-class) Wi-Fi + Bluetooth card.

The `config.plist` here is identical to `OC/config.plist` at the root of the
repository. It is kept here as well so all config variants live in one place.

## Hardware

| Component | Detail |
|---|---|
| Wi-Fi / BT | Broadcom BCM94352ZAE (DW1560-class) |
| macOS | 15 Sequoia |
| OpenCore | 1.0.6 |

## Status

| Feature | Status |
|---|---|
| Wi-Fi | ✅ Working (AirportBrcmFixup + `brcmfx-country=#a`) |
| Bluetooth (LE, Handoff) | ✅ Working (BrcmPatchRAM3 + BrcmFirmwareData + BlueToolFixup) |
| Everything else | ✅ See main README |

## Required kexts (Wi-Fi + BT specific)

- `AirportBrcmFixup.kext` v2.2.0+
- `BrcmPatchRAM3.kext` v2.7.1+
- `BrcmFirmwareData.kext` v2.7.1+
- `BlueToolFixup.kext` (included in BrcmPatchRAM release)

## Notes

- The boot-arg `brcmfx-country=#a` is already set in the config to unlock all
  Wi-Fi channels worldwide.
- No changes needed from the defaults — just replace the SMBIOS values with your
  own (see the main [Getting Started](../../README.md#getting-started-start-your-own-build) guide).
