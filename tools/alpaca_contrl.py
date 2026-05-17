#!/usr/bin/env python3
"""
Device power and EDL mode control via Alpaca TAC.

Usage:
    python3 alpaca_device_control.py power_on  [--sn <serial>]
    python3 alpaca_device_control.py power_off [--sn <serial>]
    python3 alpaca_device_control.py edl       [--sn <serial>] [--method {button,pin}]
    python3 alpaca_device_control.py list
"""

import argparse
import sys
import time
from typing import Optional

sys.path.insert(0, "/opt/qcom/Alpaca/python")

try:
    import TACDev
except Exception as e:
    print(f"ERROR: Failed to load TACDev: {e}", file=sys.stderr)
    sys.exit(1)

_OPEN_RETRIES = 3
_OPEN_RETRY_DELAY = 1.0  # seconds between retries


def _open_device(serial: Optional[str]) -> "TACDev.TacDevice":
    """Return an opened TacDevice, selected by serial number or index 0."""
    count = TACDev.GetDeviceCount()
    if count == 0:
        raise RuntimeError("No TAC devices found")

    target = None
    for i in range(count):
        dev = TACDev.GetDevice(i)
        if dev is None:
            continue
        if serial is None or dev.SerialNumber() == serial or dev.PortName() == serial:
            target = dev
            break

    if target is None:
        raise RuntimeError(
            f"Device '{serial}' not found. "
            f"Run 'list' to see available devices."
        )

    for attempt in range(1, _OPEN_RETRIES + 1):
        if target.Open():
            return target
        if attempt < _OPEN_RETRIES:
            time.sleep(_OPEN_RETRY_DELAY)

    raise RuntimeError(
        f"Could not open device '{target.PortName()}' (SN: {target.SerialNumber()}) "
        f"after {_OPEN_RETRIES} attempts"
    )


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

def cmd_list(_args) -> None:
    count = TACDev.GetDeviceCount()
    print(f"Alpaca {TACDev.AlpacaVersion()}  TAC {TACDev.TACVersion()}")
    print(f"Found {count} device(s):")
    for i in range(count):
        dev = TACDev.GetDevice(i)
        if dev:
            print(f"  [{i}] port={dev.PortName()}  sn={dev.SerialNumber()}  desc={dev.Description()}")


def cmd_power_on(args) -> None:
    dev = _open_device(args.sn)
    try:
        print(f"[power_on] Pressing power button on {dev.SerialNumber()} ...")
        dev.PowerOnButton()
        print("[power_on] Done")
    finally:
        dev.Close()


def cmd_power_off(args) -> None:
    dev = _open_device(args.sn)
    try:
        print(f"[power_off] Pressing power button on {dev.SerialNumber()} ...")
        dev.PowerOffButton()
        time.sleep(3)
        print("[power_off] Done")
    finally:
        dev.Close()


def cmd_edl(args) -> None:
    dev = _open_device(args.sn)
    try:
        method = args.method
        sn = dev.SerialNumber()

        if method == "button":
            # High-level command: TAC replays the button combo that forces EDL
            print(f"[edl] Booting {sn} to EDL via button sequence ...")
            dev.BootToEDLButton()
            print("[edl] Button sequence sent. Waiting for USB re-enumeration ...")

        elif method == "pin":
            # Assert the primary EDL pin, then power-cycle the device
            print(f"[edl] Asserting primary EDL pin on {sn} ...")
            dev.PrimaryEDL(True)
            time.sleep(0.2)

            print("[edl] Power-cycling device (battery off) ...")
            dev.SetBatteryState(False)
            time.sleep(1)

            print("[edl] Applying power (battery on) ...")
            dev.SetBatteryState(True)
            time.sleep(1)

            print("[edl] Releasing EDL pin ...")
            dev.PrimaryEDL(False)
            print("[edl] Pin sequence done. Waiting for USB re-enumeration ...")

        else:
            raise ValueError(f"Unknown EDL method: {method!r}")

        # Give the host USB stack time to detect the new device
        time.sleep(3)
        print(f"[edl] Complete. Verify with: PCAT -DEVICES")

    finally:
        dev.Close()


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Control a device via Alpaca TAC (power on/off, EDL mode)"
    )
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("list", help="List connected TAC devices")

    p_on = sub.add_parser("power_on", help="Power on the device")
    p_on.add_argument("--sn", metavar="SERIAL", help="TAC device serial / port (default: first device)")

    p_off = sub.add_parser("power_off", help="Power off the device")
    p_off.add_argument("--sn", metavar="SERIAL", help="TAC device serial / port (default: first device)")

    p_edl = sub.add_parser("edl", help="Boot device into EDL mode")
    p_edl.add_argument("--sn", metavar="SERIAL", help="TAC device serial / port (default: first device)")
    p_edl.add_argument(
        "--method",
        choices=["button", "pin"],
        default="button",
        help="button: use BootToEDLButton(); pin: assert PrimaryEDL pin + power-cycle (default: button)",
    )

    args = parser.parse_args()

    dispatch = {
        "list": cmd_list,
        "power_on": cmd_power_on,
        "power_off": cmd_power_off,
        "edl": cmd_edl,
    }

    try:
        dispatch[args.command](args)
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
