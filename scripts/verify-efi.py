#!/usr/bin/env python3
"""
verify-efi.py - offline consistency check for this OpenCore EFI.

Checks performed:
  1. Every file referenced by config.plist exists (ACPI / Drivers / Kexts / Tools).
  2. No orphan kexts / drivers sit in the EFI without a config.plist entry.
  3. Kext dependency graph: every injected kext's third-party OSBundleLibraries
     dependency is provided by another injected kext, and Lilu is injected before
     its plugins (OpenCore injects kexts in Kernel/Add order).
  4. No duplicate CFBundleIdentifier is active for the same kernel range.
  5. OpenCanopy resources exist when Misc/Boot/PickerMode is External.
  6. Broadcom BCM94352ZAE (DW1560-class) Wi-Fi/Bluetooth requirements.
  7. Installed component versions match components.lock.
  8. Optionally runs ocvalidate (--ocvalidate PATH, or --fetch-ocvalidate).

Exit code 0 = all checks passed, 1 = at least one check failed.

Usage:
    python3 scripts/verify-efi.py [--root .] [--ocvalidate /path/to/ocvalidate]
                                  [--fetch-ocvalidate]
"""

from __future__ import annotations

import argparse
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request

FAIL = "FAIL"
WARN = "WARN"
OK = "OK"

KERNEL_PROVIDED = ("com.apple.kpi.", "com.apple.kec.", "com.apple.driver.AppleMobileFileIntegrity")


class Report:
    def __init__(self) -> None:
        self.results: list[tuple[str, str, str]] = []

    def add(self, level: str, title: str, detail: str = "") -> None:
        self.results.append((level, title, detail))

    @property
    def failed(self) -> bool:
        return any(level == FAIL for level, _, _ in self.results)

    def dump(self) -> None:
        for level, title, detail in self.results:
            line = f"[{level:4}] {title}"
            print(line)
            if detail:
                for chunk in detail.splitlines():
                    print(f"       {chunk}")


def read_plist(path: str) -> dict:
    with open(path, "rb") as handle:
        return plistlib.load(handle)


def version_tuple(value: str) -> tuple:
    """Compare versions numerically; missing components count as 0 (1 == 1.0.0)."""
    parts = [int(p) for p in re.findall(r"\d+", value or "")][:4]
    while len(parts) < 4:
        parts.append(0)
    return tuple(parts)


def kernel_range(entry: dict) -> tuple:
    """Return (min, max) as comparable tuples. Empty string = unbounded."""
    low = version_tuple(entry.get("MinKernel") or "0")
    high_raw = entry.get("MaxKernel") or ""
    high = version_tuple(high_raw) if high_raw else (9999,)
    return low, high


def ranges_overlap(a: dict, b: dict) -> bool:
    a_low, a_high = kernel_range(a)
    b_low, b_high = kernel_range(b)
    return a_low <= b_high and b_low <= a_high



def collect_kexts(root: str, config: dict, report: Report) -> list[dict]:
    """Read every enabled Kernel/Add entry and return its metadata."""
    kexts = []
    for entry in config["Kernel"]["Add"]:
        if not entry.get("Enabled"):
            continue
        bundle = entry["BundlePath"]
        path = os.path.join(root, "OC", "Kexts", bundle)
        info_path = os.path.join(path, entry.get("PlistPath") or "Contents/Info.plist")
        if not os.path.isfile(info_path):
            report.add(FAIL, f"kext Info.plist missing: {bundle}", info_path)
            continue
        info = read_plist(info_path)
        kexts.append(
            {
                "bundle": bundle,
                "path": path,
                "entry": entry,
                "info": info,
                "id": info.get("CFBundleIdentifier", ""),
                "version": info.get("CFBundleVersion", ""),
            }
        )
    return kexts


def check_references(root: str, config: dict, report: Report) -> None:
    missing: list[str] = []
    for entry in config["ACPI"]["Add"]:
        if entry.get("Enabled") and not os.path.isfile(os.path.join(root, "OC", "ACPI", entry["Path"])):
            missing.append(f"ACPI/Add: {entry['Path']}")
    for entry in config["UEFI"]["Drivers"]:
        if entry.get("Enabled") and not os.path.isfile(os.path.join(root, "OC", "Drivers", entry["Path"])):
            missing.append(f"UEFI/Drivers: {entry['Path']}")
    for entry in config["Misc"]["Tools"]:
        if entry.get("Enabled") and not os.path.isfile(os.path.join(root, "OC", "Tools", entry["Path"])):
            missing.append(f"Misc/Tools: {entry['Path']}")
    for entry in config["Kernel"]["Add"]:
        if not entry.get("Enabled"):
            continue
        base = os.path.join(root, "OC", "Kexts", entry["BundlePath"])
        if not os.path.isfile(os.path.join(base, entry.get("PlistPath") or "Contents/Info.plist")):
            missing.append(f"Kernel/Add: {entry['BundlePath']}")
        exec_path = entry.get("ExecutablePath") or ""
        if exec_path and not os.path.isfile(os.path.join(base, exec_path)):
            missing.append(f"Kernel/Add executable: {entry['BundlePath']}/{exec_path}")

    if missing:
        report.add(FAIL, f"{len(missing)} config.plist reference(s) point at missing files", "\n".join(missing))
    else:
        report.add(OK, "every config.plist reference resolves to a file on disk")


def check_orphans(root: str, config: dict, report: Report) -> None:
    referenced_kexts = {e["BundlePath"].split("/")[0] for e in config["Kernel"]["Add"]}
    on_disk = {n for n in os.listdir(os.path.join(root, "OC", "Kexts")) if n.endswith(".kext")}
    orphans = sorted(on_disk - referenced_kexts)
    if orphans:
        report.add(WARN, "kexts present in OC/Kexts but never injected", "\n".join(orphans))
    else:
        report.add(OK, "no orphan kexts in OC/Kexts")

    referenced_drivers = {e["Path"] for e in config["UEFI"]["Drivers"]}
    drivers_on_disk = {n for n in os.listdir(os.path.join(root, "OC", "Drivers")) if n.endswith(".efi")}
    extra = sorted(drivers_on_disk - referenced_drivers)
    if extra:
        report.add(WARN, "drivers present in OC/Drivers but not listed in config.plist", "\n".join(extra))
    else:
        report.add(OK, "no orphan drivers in OC/Drivers")


def check_dependencies(kexts: list[dict], report: Report) -> None:
    provided = {k["id"]: k for k in kexts if k["id"]}
    problems: list[str] = []
    for kext in kexts:
        libs = kext["info"].get("OSBundleLibraries", {}) or {}
        for dep, needed in libs.items():
            if dep.startswith(KERNEL_PROVIDED):
                continue
            provider = provided.get(dep)
            if provider is None:
                if dep.startswith("com.apple."):
                    continue  # Apple kext shipped with macOS itself
                problems.append(f"{kext['bundle']} requires {dep} >= {needed} but nothing injects it")
                continue
            if version_tuple(provider["version"]) < version_tuple(needed):
                problems.append(
                    f"{kext['bundle']} requires {dep} >= {needed} but injected version is {provider['version']}"
                )
    if problems:
        report.add(FAIL, f"{len(problems)} unsatisfied kext dependency(ies)", "\n".join(problems))
    else:
        report.add(OK, "every injected kext dependency is satisfied by the injected set")


def check_lilu_order(kexts: list[dict], report: Report) -> None:
    order = {k["id"]: i for i, k in enumerate(kexts)}
    lilu = order.get("as.vit9696.Lilu")
    if lilu is None:
        report.add(FAIL, "Lilu.kext is not injected")
        return
    late = [
        k["bundle"]
        for k in kexts
        if "as.vit9696.Lilu" in (k["info"].get("OSBundleLibraries") or {}) and order[k["id"]] < lilu
    ]
    if late:
        report.add(FAIL, "Lilu.kext must be injected before its plugins", "\n".join(late))
    else:
        report.add(OK, "Lilu is injected before every Lilu plugin")


def check_duplicate_ids(kexts: list[dict], report: Report) -> None:
    by_id: dict[str, list[dict]] = {}
    for kext in kexts:
        by_id.setdefault(kext["id"], []).append(kext)
    clashes: list[str] = []
    for ident, group in by_id.items():
        if len(group) < 2:
            continue
        for i in range(len(group)):
            for j in range(i + 1, len(group)):
                if ranges_overlap(group[i]["entry"], group[j]["entry"]):
                    clashes.append(
                        f"{ident}: {group[i]['bundle']} overlaps {group[j]['bundle']} "
                        f"(same macOS range)"
                    )
    if clashes:
        report.add(FAIL, "duplicate CFBundleIdentifier active for the same macOS range", "\n".join(clashes))
    else:
        report.add(OK, "no conflicting duplicate kext identifiers (range-bounded duplicates are fine)")



def check_open_canopy(root: str, config: dict, report: Report) -> None:
    picker = config["Misc"]["Boot"].get("PickerMode", "Builtin")
    if picker != "External":
        report.add(OK, f"picker mode is {picker} (OpenCanopy resources not required)")
        return
    missing = []
    for sub in ("Font", "Image", "Label"):
        folder = os.path.join(root, "OC", "Resources", sub)
        if not os.path.isdir(folder) or not os.listdir(folder):
            missing.append(f"OC/Resources/{sub}")
    if missing:
        report.add(FAIL, "PickerMode=External but OpenCanopy resources are missing", "\n".join(missing))
    else:
        report.add(OK, "OpenCanopy resources present for PickerMode=External")


def check_broadcom(root: str, config: dict, report: Report, kexts: list[dict]) -> None:
    """BCM94352ZAE (DW1560-class) specific requirements."""
    problems: list[str] = []
    ids = {k["id"]: k for k in kexts}

    def args() -> list[str]:
        guid = "7C436110-AB2A-4BBB-A880-FE41995C9F82"
        return (config["NVRAM"]["Add"].get(guid, {}).get("boot-args") or "").split()

    nvram = config["NVRAM"]["Add"].get("7C436110-AB2A-4BBB-A880-FE41995C9F82", {})
    deletes = config["NVRAM"]["Delete"].get("7C436110-AB2A-4BBB-A880-FE41995C9F82", [])
    csr = nvram.get("csr-active-config") or b""

    if "as.lvs1974.AirportBrcmFixup" not in ids:
        problems.append("AirportBrcmFixup.kext is not injected")
    if "as.lvs1974.AirportBrcmNICInjector" not in ids:
        problems.append("AirPortBrcmNIC_Injector.kext is not injected (needed to bind BCM4352 to AirPortBrcmNIC)")
    if "as.lvs1974.AirportBrcm4360Injector" in ids:
        problems.append("AirPortBrcm4360_Injector.kext must stay disabled on macOS 11+")
    for ident in ("as.acidanthera.BrcmPatchRAM3", "as.acidanthera.BrcmFirmwareStore", "as.acidanthera.BlueToolFixup"):
        if ident not in ids:
            problems.append(f"{ident} is missing (Broadcom Bluetooth on macOS 12+)")
    for ident in ("com.apple.iokit.IOSkywalkFamily", "com.apple.iokit.IO80211FamilyLegacy", "com.apple.driver.AirPort.BrcmNIC"):
        if ident not in ids:
            problems.append(f"{ident} is not injected (OCLP legacy Wi-Fi stack for macOS 14+)")

    blocked = [b for b in config["Kernel"]["Block"] if b.get("Enabled") and b.get("Identifier") == "com.apple.iokit.IOSkywalkFamily"]
    if not blocked:
        problems.append("com.apple.iokit.IOSkywalkFamily is not blocked in Kernel/Block (required to load the injected copy)")

    if "brcmfx-country=" not in " ".join(args()):
        problems.append("boot-args is missing brcmfx-country=XX")
    if "-brcmfxbeta" not in args():
        problems.append("boot-args is missing -brcmfxbeta (AirportBrcmFixup refuses unsupported macOS 14+ otherwise)")
    if nvram.get("bluetoothInternalControllerInfo") != bytes(12):
        problems.append("NVRAM bluetoothInternalControllerInfo must be 12 zero bytes (BrcmPatchRAM >= 2.7.0)")
    if nvram.get("bluetoothExternalDongleFailed") != b"\x00":
        problems.append("NVRAM bluetoothExternalDongleFailed must be 00 (BrcmPatchRAM >= 2.7.0)")
    for key in ("bluetoothInternalControllerInfo", "bluetoothExternalDongleFailed"):
        if key not in deletes:
            problems.append(f"NVRAM/Delete must list {key} so the value is not inherited")
    if csr[:4] != bytes([0x03, 0x08, 0x00, 0x00]):
        problems.append(f"csr-active-config is {csr.hex() or 'unset'}, expected 03080000 (OCLP root patching)")
    if config["Misc"]["Security"].get("SecureBootModel") != "Disabled":
        problems.append("SecureBootModel must be Disabled for OCLP root patching")

    if problems:
        report.add(FAIL, f"{len(problems)} Broadcom BCM94352ZAE requirement(s) not met", "\n".join(problems))
    else:
        report.add(OK, "Broadcom BCM94352ZAE Wi-Fi/Bluetooth requirements are all met")




def sha256_file(path: str) -> str:
    import hashlib

    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def check_manifest(root: str, kexts: list[dict], report: Report, write_hashes: bool = False) -> None:
    lock_path = os.path.join(root, "components.lock")
    if not os.path.isfile(lock_path):
        report.add(WARN, "components.lock not found - skipping version pinning check")
        return
    with open(lock_path) as handle:
        lock = json.load(handle)

    mismatches: list[str] = []
    for record in lock.get("kexts", []):
        info_path = os.path.join(root, record["bundle_path"], "Contents", "Info.plist")
        if not os.path.isfile(info_path):
            mismatches.append(f"{record['bundle_path']}: listed in components.lock but missing on disk")
            continue
        installed = read_plist(info_path).get("CFBundleVersion")
        if str(installed) != str(record["version"]):
            mismatches.append(
                f"{record['name']}: components.lock says {record['version']}, "
                f"on-disk Info.plist says {installed}"
            )
    if mismatches:
        report.add(FAIL, f"{len(mismatches)} component version mismatch(es) vs components.lock", "\n".join(mismatches))
    else:
        report.add(OK, f"all {len(lock.get('kexts', []))} kexts match components.lock (OpenCore {lock.get('opencore_version')})")

    core = lock.get("core_sha256", {})
    if write_hashes:
        for rel in core:
            core[rel] = sha256_file(os.path.join(root, rel))
        with open(lock_path, "w") as handle:
            json.dump(lock, handle, indent=2)
            handle.write("\n")
        report.add(OK, "components.lock hashes refreshed")
        return
    bad = []
    for rel, expected in core.items():
        path = os.path.join(root, rel)
        if not os.path.isfile(path):
            bad.append(f"{rel}: missing")
        elif sha256_file(path) != expected:
            bad.append(f"{rel}: sha256 differs from the pinned OpenCore {lock.get('opencore_version')} build")
    if bad:
        report.add(FAIL, "OpenCore core binaries do not match the pinned release", "\n".join(bad))
    else:
        report.add(OK, f"OpenCore core binaries match the pinned {lock.get('opencore_version')} release hashes")


def fetch_ocvalidate(report: Report) -> str | None:
    """Download ocvalidate.linux for the pinned OpenCore version into a temp dir."""
    version = "1.0.8"
    if os.path.isfile("components.lock"):
        with open("components.lock") as handle:
            version = json.load(handle).get("opencore_version", version)
    url = (
        f"https://github.com/acidanthera/OpenCorePkg/releases/download/{version}/"
        f"OpenCore-{version}-RELEASE.zip"
    )
    try:
        import zipfile

        with tempfile.TemporaryDirectory() as tmp:
            archive = os.path.join(tmp, "oc.zip")
            urllib.request.urlretrieve(url, archive)
            with zipfile.ZipFile(archive) as zf:
                member = "Utilities/ocvalidate/ocvalidate.linux"
                if member not in zf.namelist():
                    report.add(WARN, "ocvalidate.linux not present in the OpenCore release archive")
                    return None
                zf.extract(member, tmp)
            keep = os.path.join(tempfile.gettempdir(), f"ocvalidate-{version}.linux")
            shutil.copy2(os.path.join(tmp, "Utilities", "ocvalidate", "ocvalidate.linux"), keep)
            os.chmod(keep, 0o755)
            return keep
    except Exception as exc:  # network problems must not fail the whole run
        report.add(WARN, f"could not download ocvalidate {version}: {exc}")
        return None


def check_ocvalidate(root: str, report: Report, ocvalidate: str | None, fetch: bool) -> None:
    binary = ocvalidate
    if not binary and fetch:
        binary = fetch_ocvalidate(report)
    if not binary:
        report.add(WARN, "ocvalidate not run (pass --ocvalidate PATH or --fetch-ocvalidate)")
        return
    result = subprocess.run([binary, os.path.join(root, "OC", "config.plist")], capture_output=True, text=True)
    output = (result.stdout or "") + (result.stderr or "")
    if "No issues found" in output:
        report.add(OK, f"ocvalidate: {os.path.basename(binary)} reports no issues with config.plist")
    else:
        report.add(FAIL, f"ocvalidate reported problems ({os.path.basename(binary)})", output.strip())


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify this OpenCore EFI for the Dell Latitude 5400.")
    parser.add_argument("--root", default=".", help="repository root (default: current directory)")
    parser.add_argument("--ocvalidate", help="path to an ocvalidate binary")
    parser.add_argument("--fetch-ocvalidate", action="store_true", help="download ocvalidate for the pinned version")
    parser.add_argument("--write-hashes", action="store_true", help="refresh the core hashes in components.lock")
    args = parser.parse_args()

    root = os.path.abspath(args.root)
    report = Report()
    config = read_plist(os.path.join(root, "OC", "config.plist"))
    kexts = collect_kexts(root, config, report)

    check_references(root, config, report)
    check_orphans(root, config, report)
    check_dependencies(kexts, report)
    check_lilu_order(kexts, report)
    check_duplicate_ids(kexts, report)
    check_open_canopy(root, config, report)
    check_broadcom(root, config, report, kexts)
    check_manifest(root, kexts, report, write_hashes=args.write_hashes)
    check_ocvalidate(root, report, args.ocvalidate, args.fetch_ocvalidate)

    report.dump()
    failures = sum(1 for level, _, _ in report.results if level == FAIL)
    warnings = sum(1 for level, _, _ in report.results if level == WARN)
    print(f"\n{len(report.results)} checks: {len(report.results) - failures - warnings} ok, {warnings} warnings, {failures} failures")
    return 1 if report.failed else 0


if __name__ == "__main__":
    sys.exit(main())

