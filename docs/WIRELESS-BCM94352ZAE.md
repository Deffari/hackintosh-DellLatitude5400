# Broadcom BCM94352ZAE (DW1560-class) — what the swapped card needs

This laptop does **not** have its stock Intel Wireless-AC 9560 any more. The installed card is a
**Broadcom BCM94352ZAE** (DW1560-class, chip BCM4352 + BCM20702 Bluetooth), and that changes
what the EFI must contain on modern macOS.

## 1. Hardware facts

| | |
|-|-|
| Wi-Fi chip | BCM4352, PCI id `14e4:43b1` (`pci14e4,43b1`) |
| Wi-Fi driver class in macOS | `AirPortBrcmNIC` (was `AirPortBrcm4360` before 10.14) |
| Bluetooth chip | BCM20702, USB `0a5c:216f` (RAMUSB — firmware uploaded at every boot) |
| BT attachment | **USB 2.0 lines of the M.2 slot** — so it only works if that internal USB port is mapped |
| USB map in this repo | `OC/Kexts/USBPorts.kext` maps `HS06`, `HS07`, `HS10` as `UsbConnector 255` (internal) — that is where the card's Bluetooth sits |

## 2. macOS support matrix for this chip (verified against upstream)

| macOS | Wi-Fi | Bluetooth | Notes |
|-|-|-|-|
| 13 Ventura and older | works with AirportBrcmFixup | works with BrcmPatchRAM3 + BlueToolFixup | native driver still present |
| 14 Sonoma | **only with OCLP root patches** | works | `AirPortBrcmNIC` removed from the OS |
| 15 Sequoia (target here) | **only with OCLP root patches** | works | same, plus mandatory BT NVRAM vars |
| 26 Tahoe | **only with OCLP root patches** | works (BrcmPatchRAM 2.7.2 adds macOS 26 `bluetoothd` patches) | Tahoe-specific `AirPortBrcmNIC` payload required |

Sources: AirportBrcmFixup README (`[14+] Use with OCLP`), the OCLP "Modern Wireless" patch
set (`AirPortBrcmNICThirdParty` — "we'll throw a bone to hackintosh users"), and the OCLP
payload list (`IO80211FamilyLegacy-v1.0.0`, `IOSkywalkFamily-v1.2.0`,
`AirPortBrcmNIC-Tahoe-v1.0.0`, `AMFIPass-v1.4.1`).

`AppleBCMWLANCompanion` (the "no root patches" alternative) supports **BCM43602 (`43ba`) and
BCM4350 (`43a3`) only** — it does *not* cover our `43b1`, so it is not an option here.

## 3. What this EFI now contains for the card

**Injected kexts** (in `Kernel/Add` order, `MinKernel`/`MaxKernel` as listed):

| Kext | Min | Max | Purpose |
|-|-|-|-|
| `IOSkywalkFamily.kext` | 23.0.0 | — | patched IOSkywalk the legacy Wi-Fi stack needs |
| `IO80211FamilyLegacy.kext` | 23.0.0 | — | legacy 802.11 framework |
| `…/PlugIns/AirPortBrcmNIC.kext` | 23.0.0 | 24.99.99 | BCM4352 driver for Sonoma/Sequoia |
| `AirPortBrcmNIC-Tahoe.kext` | 25.0.0 | — | BCM4352 driver for macOS 26 |
| `ECM-Override.kext` | 23.0.0 | — | keeps USB-C dock (ECM) Ethernet alive with IOSkywalk downgraded |
| `AMFIPass.kext` | 20.0.0 | — | boots with AMFI enabled on a root-patched system |
| `AirportBrcmFixup.kext` + `AirPortBrcmNIC_Injector.kext` | 12.0.0 / 21.0.0 | — | injects `43a0` device-id so `AirPortBrcmNIC` binds to `43b1`, country code, WOWL fixes |
| `AirPortBrcm4360_Injector.kext` | — | 20.9.9 | **disabled** — must never load on macOS 11+ |
| `BlueToolFixup.kext`, `BrcmFirmwareData.kext`, `BrcmPatchRAM3.kext` | 21.0.0 | — | Bluetooth firmware upload + user-space `bluetoothd` patches |

**`Kernel/Block`:** `com.apple.iokit.IOSkywalkFamily` (`Strategy: Exclude`, `MinKernel 23.0.0`)
so the injected copy wins.

**Boot-args** (relevant ones): `brcmfx-country=#a` (world/`#a` regulatory domain),
`-brcmfxbeta` (AirportBrcmFixup refuses to patch on "unsupported" macOS 14+ without it),
`-btlfxboardid` (BlueToolFixup board-id workaround for macOS 14+ with BrcmPatchRAM >= 2.7.0),
`ipc_control_port_options=0` (Electron apps with lowered SIP).

**NVRAM** (`7C436110-…-FE41995C9F82`): `bluetoothInternalControllerInfo` = 12 zero bytes,
`bluetoothExternalDongleFailed` = `00` — mandatory for BrcmPatchRAM >= 2.7.0, both also listed
in `NVRAM/Delete` so a stale value is never inherited.

## 4. Required post-install step: OCLP root patches

The kexts above make the *driver* available; the OS side (frameworks, `airportd`,
`wifip2pd`, `CoreWLAN`/`CoreWiFi`) still has to be patched. That is what OpenCore Legacy
Patcher does — it is a normal app you run **inside the installed macOS**:

1. Install macOS (see `docs/USB-CREATION.md`). Ethernet works without any patches, so you
   can complete the install and any updates with a cable.
2. Download OpenCore Legacy Patcher (latest release; 2.5.1 at the time of writing) and run it.
3. `Post-Install Root Patch` → **Modern Wireless** (it detects `14e4:43b1` as a third-party
   Broadcom chipset) → apply, then reboot.
4. Wi-Fi comes up; Continuity (AirDrop/Handoff) needs the card's Bluetooth working too,
   which the EFI already provides.

OCLP's own validation requires exactly what this EFI now sets — SIP lowered
(`csr-active-config = 03080000`) and `SecureBootModel = Disabled` — otherwise it refuses to
apply the root patches.

### Verifying on macOS

```bash
# card visible on the PCI bus and bound to the Apple driver
ioreg -l | grep -i "IONameMatched.*pci14e4"     # expect pci14e4,43b1 -> AirPortBrcmNIC
system_profiler SPNetworkDataType | grep -A4 -i wi-fi
# Bluetooth
system_profiler SPBluetoothDataType | head -20
log show --last 5m --predicate 'process == "bluetoothd"' | grep -i -E "Brcm|BlueTool" 
```

## 5. Why SIP/SecureBootModel changed, and how to go back

`csr-active-config = 03080000` (SIP partially disabled) and `SecureBootModel = Disabled` are
**required** for OCLP root patching and for the patched kexts/frameworks to load. They do
lower the system's security posture, so they are listed here explicitly:

| Key | Value now | Stock/secure value |
|-|-|-|
| `NVRAM/Add/…-FE41995C9F82/csr-active-config` | `03080000` | `00000000` |
| `Misc/Security/SecureBootModel` | `Disabled` | `Default` |

To go back to a fully secured, unpatched system (Wi-Fi on macOS 14+ will stop working, or
will stop working after the next OS update that reverts the patches):

1. Delete the six OCLP kext entries from `Kernel/Add` (`IOSkywalkFamily`,
   `IO80211FamilyLegacy` + `AirPortBrcmNIC` plugin, `AirPortBrcmNIC-Tahoe`, `ECM-Override`,
   `AMFIPass`) and the kexts from `OC/Kexts`.
2. Delete the `com.apple.iokit.IOSkywalkFamily` entry from `Kernel/Block`.
3. Remove `-brcmfxbeta`, `-btlfxboardid`, `ipc_control_port_options=0` from `boot-args`.
4. Restore `csr-active-config` and `SecureBootModel` as in the table above.
5. Keep the Bluetooth NVRAM variables and `AirportBrcmFixup`/`BrcmPatchRAM` — they are
   harmless and still needed for the card.
6. Run `python3 scripts/verify-efi.py` (the Broadcom checks will fail on purpose — that is
   the tool telling you Wi-Fi is no longer set up) and `ocvalidate`.

## 6. Bluetooth specifics & troubleshooting

* The card's Bluetooth is a **RAMUSB** device: `BrcmPatchRAM3` uploads firmware on every
  boot/wake, `BrcmFirmwareData` supplies it, `BlueToolFixup` patches the user-space
  `bluetoothd` (macOS 12+; 2.7.2 adds the macOS 26 patches).
* It only appears if the M.2 slot's USB port is mapped as internal — already done in
  `USBPorts.kext` (`HS06`/`HS07`/`HS10`). Do not "clean up" those entries.
* Wake-from-sleep flakiness is a known RAMUSB symptom; upstream suggests adding
  `bpr_probedelay=100 bpr_initialdelay=300 bpr_postresetdelay=300` to `boot-args`.
* If two Bluetooth devices end up with the same address (macOS 12.4+ rejects that), add
  `-btlfxallowanyaddr`.
* `NVRAM -p | grep bluetoothExternalDongleFailed` should print `%00`; if it is `%01`,
  `sudo nvram bluetoothExternalDongleFailed=%00` then `sudo pkill bluetoothd`.

## 7. If the card is ever swapped again

* **Back to the stock Intel 9560**: remove the Broadcom entries above, re-add
  `AirportItlwm` (macOS <= 13) or `itlwm` + HelioPort (macOS 14+, where `AirportItlwm` is no
  longer usable) and `IntelBluetoothFirmware` + `BlueToolFixup`; Intel Wi-Fi needs **no**
  root patches and no SIP changes.
* **Any other Broadcom card**: check the device id against
  `AppleBCMWLANCompanion` (`43ba`, `43a3` → no root patches) or the OCLP third-party list
  (`4357`, `43b1`, `43b2` → root patches). Then update `Kernel/Add` and re-run
  `scripts/verify-efi.py` and `scripts/check-updates.py`.

