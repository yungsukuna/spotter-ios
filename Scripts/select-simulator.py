#!/usr/bin/env python3
"""Print the UDID of the best available iPhone simulator on this machine.

Hardcoding a simulator name (e.g. "iPhone 16") in CI is the usual reason iOS
pipelines break months later: GitHub rotates the runner image, that device
stops existing, and xcodebuild fails with an unhelpful destination error.
This resolves one at runtime instead.

Preference order: highest iOS runtime, then highest iPhone model number.
"""

import json
import re
import subprocess
import sys


def runtime_version(runtime_id: str) -> tuple[int, ...]:
    """'com.apple.CoreSimulator.SimRuntime.iOS-18-2' -> (18, 2)"""
    match = re.search(r"iOS-([\d-]+)$", runtime_id)
    if not match:
        return (0,)
    return tuple(int(part) for part in match.group(1).split("-"))


def model_number(name: str) -> tuple[int, int]:
    """Rank iPhone models so 'iPhone 17 Pro' outranks 'iPhone 16'."""
    match = re.search(r"iPhone\s+(\d+)", name)
    number = int(match.group(1)) if match else 0
    # Prefer the plain model over Pro/Max/mini variants: fewer surprises, and
    # the base device is always present on the runner image.
    is_variant = 1 if re.search(r"(Pro|Max|mini|Plus)", name) else 0
    return (number, -is_variant)


def main() -> int:
    raw = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "available", "--json"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    devices_by_runtime = json.loads(raw)["devices"]

    candidates = []
    for runtime_id, devices in devices_by_runtime.items():
        if "iOS" not in runtime_id:
            continue
        for device in devices:
            if not device.get("isAvailable"):
                continue
            if not device["name"].startswith("iPhone"):
                continue
            sort_key = (runtime_version(runtime_id), model_number(device["name"]))
            candidates.append((sort_key, device["udid"], device["name"], runtime_id))

    if not candidates:
        print("No available iPhone simulator found on this machine.", file=sys.stderr)
        print("Runtimes seen: " + ", ".join(devices_by_runtime), file=sys.stderr)
        return 1

    _, udid, name, runtime_id = max(candidates, key=lambda c: c[0])
    print(f"Selected {name} on {runtime_id}", file=sys.stderr)
    print(udid)
    return 0


if __name__ == "__main__":
    sys.exit(main())
