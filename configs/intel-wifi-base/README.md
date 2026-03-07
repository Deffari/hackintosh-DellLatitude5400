# Config: Intel Wireless-AC 9560 (stock card) — Wi-Fi working, Bluetooth needs setup

This config is based on the main Dell Latitude 5400 EFI but adapted for the
**stock Intel Wireless-AC 9560** card that ships with the laptop. Wi-Fi works
out of the box with `AirportItlwm`. Bluetooth requires a few extra steps
(described below).

## Status

| Feature | Status | Notes |
|---|---|---|
| Wi-Fi | ✅ Working | AirportItlwm (native AirPort stack) |
| Bluetooth | ⚠️ Needs setup | See steps below |
| Everything else | ✅ Same as main EFI | |

## Required kexts (Wi-Fi + BT specific)

Download and place these in `EFI/OC/Kexts/` **instead of** the Broadcom kexts:

| Kext | Purpose | Download |
|---|---|---|
| `AirportItlwm.kext` | Intel Wi-Fi (native AirPort API) | [OpenIntelWireless releases](https://github.com/OpenIntelWireless/itlwm/releases) — use the **Sequoia** variant |
| `IntelBluetoothFirmware.kext` | Intel BT firmware uploader | [IntelBluetoothFirmware releases](https://github.com/OpenIntelWireless/IntelBluetoothFirmware/releases) |
| `IntelBTPatcher.kext` | Intel BT compatibility patcher for macOS 12+ | same package as IntelBluetoothFirmware above |
| `BlueToolFixup.kext` | Required for Intel BT to work in macOS 12+ | [BrcmPatchRAM releases](https://github.com/acidanthera/BrcmPatchRAM/releases) (it ships with BrcmPatchRAM even for Intel) |

> **Remove** `AirportBrcmFixup.kext`, `BrcmFirmwareData.kext`, and
> `BrcmPatchRAM3.kext` — they are not needed for the Intel card.

## Setting up Bluetooth step by step

### Step 1 — Download the Intel BT kexts

1. Go to <https://github.com/OpenIntelWireless/IntelBluetoothFirmware/releases>
2. Download the latest release zip (e.g. `IntelBluetoothFirmware-2.4.0.zip`)
3. Extract it. You will find:
   - `IntelBluetoothFirmware.kext`
   - `IntelBTPatcher.kext`

### Step 2 — Download BlueToolFixup

1. Go to <https://github.com/acidanthera/BrcmPatchRAM/releases>
2. Download the latest release zip
3. Extract it. You will find `BlueToolFixup.kext` inside

### Step 3 — Add the kexts to your EFI

Copy all three kexts into `EFI/OC/Kexts/`:
```
EFI/OC/Kexts/BlueToolFixup.kext
EFI/OC/Kexts/AirportItlwm.kext        (already in main EFI if you replaced)
EFI/OC/Kexts/IntelBluetoothFirmware.kext
EFI/OC/Kexts/IntelBTPatcher.kext
```

### Step 4 — Verify config.plist entries

Open this `config.plist` in [ProperTree](https://github.com/corpnewt/ProperTree)
and confirm that `Kernel > Add` contains entries for all four kexts above,
all with `Enabled = true`. This config already has the correct entries.

**Load order matters!** Make sure the order in `Kernel > Add` is:
1. `Lilu.kext` (must be first)
2. `BlueToolFixup.kext`
3. `AirportItlwm.kext`
4. `IntelBluetoothFirmware.kext`
5. `IntelBTPatcher.kext`

### Step 5 — Generate your own SMBIOS

Replace the placeholder values in `PlatformInfo > Generic`:
- `SystemSerialNumber` → your generated serial
- `MLB` → your generated MLB
- `SystemUUID` → your generated UUID
- `ROM` → your MAC address (6 bytes as Base64 in the data field)

Use [GenSMBIOS](https://github.com/corpnewt/GenSMBIOS) with model
**MacBookPro15,4** (the same model already set in this config).

### Step 6 — Reboot and test

After placing all kexts and updating the config:
1. Boot macOS
2. Open **System Settings → Bluetooth** — it should show the adapter
3. If Bluetooth is not visible, open **Console.app** and filter for `bluetooth`
   to look for firmware upload errors

## Known limitations with Intel card

- Wi-Fi scanning can be slower than with native Broadcom/Apple cards
- Handoff / AirDrop may not work as reliably as with Broadcom
- Apple can change the Wi-Fi subsystem in any macOS update, potentially
  breaking Intel kext support (this happened with Ventura in the past)

For the best long-term experience, replace the Intel 9560 with a
**Broadcom BCM94352ZAE (DW1560-class)** card and use the
[`broadcom-wifi-bt/`](../broadcom-wifi-bt/) config instead.

## Replacing your config.plist with your own version

If you have your own working (or almost-working) `config.plist`, just replace
this file with yours:

```bash
# On macOS, mount your EFI partition, then:
cp /path/to/your/config.plist /Volumes/EFI/EFI/OC/config.plist
```

Or in this repository: simply overwrite `configs/intel-wifi-base/config.plist`
with your file and open a Pull Request.
