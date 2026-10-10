#!/usr/bin/env python3
"""
check-updates.py - compare the pinned components.lock with the latest upstream releases.

Works offline-ish: uses `gh api` when the GitHub CLI is available, otherwise falls
back to plain HTTPS requests. Read-only - it never modifies the EFI, it only prints
what is newer than what is currently committed.

Usage:
    python3 scripts/check-updates.py
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import urllib.request

LOCK = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "components.lock")

# upstream repository -> component name in components.lock
REPO_FOR_UPSTREAM = {
    "acidanthera/Lilu": "Lilu",
    "acidanthera/VirtualSMC": "VirtualSMC",
    "acidanthera/WhateverGreen": "WhateverGreen",
    "acidanthera/AppleALC": "AppleALC",
    "acidanthera/AirportBrcmFixup": "AirportBrcmFixup",
    "acidanthera/BrcmPatchRAM": "BrcmPatchRAM",
    "acidanthera/CPUFriend": "CPUFriend",
    "acidanthera/IntelMausi": "IntelMausi",
    "acidanthera/NVMeFix": "NVMeFix",
    "acidanthera/RestrictEvents": "RestrictEvents",
    "acidanthera/BrightnessKeys": "BrightnessKeys",
    "acidanthera/VoodooPS2": "VoodooPS2",
    "VoodooI2C/VoodooI2C": "VoodooI2C",
    "0xFireWolf/RealtekCardReader": "RealtekCardReader",
    "0xFireWolf/RealtekCardReaderFriend": "RealtekCardReaderFriend",
    "blankmac/AlpsHID": "AlpsHID",
}

# OCLP payload kexts are versioned by file name inside the repository
OCLP_PAYLOADS = {
    "IOSkywalkFamily": "payloads/Kexts/Wifi",
    "IO80211FamilyLegacy": "payloads/Kexts/Wifi",
    "AirPortBrcmNIC-Tahoe": "payloads/Kexts/Wifi",
    "ECM-Override": "payloads/Kexts/Misc",
    "AMFIPass": "payloads/Kexts/Acidanthera",
}


def gh_api(path: str):
    try:
        out = subprocess.run(
            ["gh", "api", path], capture_output=True, text=True, timeout=60, check=True
        )
        return json.loads(out.stdout)
    except Exception:
        request = urllib.request.Request(
            "https://api.github.com" + path, headers={"Accept": "application/vnd.github+json"}
        )
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return json.load(response)
        except Exception as exc:
            print(f"  ! could not query {path}: {exc}")
            return None


def latest_release_tag(repo: str) -> str | None:
    data = gh_api(f"/repos/{repo}/releases/latest")
    return data.get("tag_name") if isinstance(data, dict) else None


def oclp_payload_version(folder: str, prefix: str) -> str | None:
    data = gh_api(f"/repos/dortania/OpenCore-Legacy-Patcher/contents/{folder}")
    if not isinstance(data, list):
        return None
    for item in data:
        name = item.get("name", "")
        if name.startswith(prefix + "-v") and name.endswith(".zip"):
            return name[len(prefix) + 2 : -4]
    return None


def compare(current: str, latest: str | None) -> str:
    if latest is None:
        return "unknown"
    strip = lambda v: v.lstrip("v").strip()
    return "up to date" if strip(current) == strip(latest) else f"UPDATE -> {latest}"


def main() -> int:
    with open(LOCK) as handle:
        lock = json.load(handle)

    print(f"Pinned OpenCore: {lock['opencore_version']} ({lock['opencore_source']})")
    latest_oc = latest_release_tag("acidanthera/OpenCorePkg")
    print(f"Latest OpenCore: {latest_oc}  [{compare(lock['opencore_version'], latest_oc)}]\n")

    print("Kexts:")
    checked = set()
    for record in lock.get("kexts", []):
        upstream = record.get("upstream", "")
        if upstream in REPO_FOR_UPSTREAM:
            if upstream in checked:
                continue
            checked.add(upstream)
            latest = latest_release_tag(upstream)
            status = compare(record["upstream_version"], latest)
            print(f"  {record['name']:<52} {record['upstream_version']:<10} {status}")
        elif upstream == "dortania/OpenCore-Legacy-Patcher":
            payload = next((k for k in OCLP_PAYLOADS if k in record["bundle_path"]), None)
            if payload is None or payload in checked:
                continue
            checked.add(payload)
            latest = oclp_payload_version(OCLP_PAYLOADS[payload], payload)
            status = compare(record["upstream_version"], latest)
            print(f"  {record['name']:<52} {record['upstream_version']:<10} {status}")

    oclp = latest_release_tag("dortania/OpenCore-Legacy-Patcher")
    print(f"\nOCLP (needed for Broadcom Wi-Fi on macOS 14+ root patches): latest release {oclp}")
    print("Run 'python3 scripts/verify-efi.py --ocvalidate <path>' after any component update.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

