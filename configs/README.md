# Alternative EFI Configs

This directory holds ready-to-use `config.plist` variants for different hardware configurations of the Dell Latitude 5400.

## Available Configs

| Folder | Wi-Fi Card | Wi-Fi | Bluetooth | Status |
|---|---|---|---|---|
| [`broadcom-wifi-bt/`](broadcom-wifi-bt/) | BCM94352ZAE (DW1560-class) | ✅ Working | ✅ Working | **Recommended / Main config** |
| [`intel-wifi-base/`](intel-wifi-base/) | Intel Wireless-AC 9560 (stock) | ✅ Working | ⚠️ Needs BT setup | Good starting point for stock card users |

## How to Use

1. Choose the config folder that matches your Wi-Fi/Bluetooth card
2. Copy the `config.plist` from that folder to `EFI/OC/config.plist` on your EFI partition
3. Read the `README.md` inside the folder for any card-specific kext requirements or steps
4. **Generate your own SMBIOS** before booting — never reuse the placeholder values

## How to Contribute Your Config

If you have a working or almost-working `config.plist` for a hardware variant not listed here:

1. Create a new subfolder with a descriptive name (e.g. `my-variant/`)
2. Add your `config.plist` (with placeholder SMBIOS values — **do not commit real serial numbers**)
3. Add a `README.md` describing:
   - Which hardware it targets
   - What works and what doesn't
   - Any required kexts that differ from the main EFI
4. Open a Pull Request
