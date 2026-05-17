# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

This repo contains a bash script to test ADB stability on Qualcomm platforms (X1E80100 EVK) by performing hardware power cycles via an Alpaca TAC unit and verifying ADB reconnection after each cycle.

## Running the Test

```bash
./adb_reboot_stability_test.sh [DEVICE_SERIAL] [ALPACA_SN] [ITERATIONS]
```

Defaults: device=`bbc3d4d2`, alpaca=`FTAGZXRO`, iterations=`10`

Example:
```bash
./adb_reboot_stability_test.sh bbc3d4d2 FTAGZXRO 20
```

The script writes its log to `/tmp/adb_reboot_stability_<timestamp>.log`. Failures are additionally written to `/tmp/adb_reboot_failures.log`.

## Dependencies

- `adb` — Android Debug Bridge, must be on PATH
- `python3 tools/alpaca_contrl.py` — Alpaca TAC control script (not in this repo; expected at `tools/alpaca_contrl.py` relative to the script)

## Architecture

The script is a single bash file (`adb_reboot_stability_test.sh`) with this flow per cycle:

1. **Power off** — calls `alpaca_contrl.py power_off --sn <ALPACA_SN>`
2. **5s delay** — allows the device to fully shut down
3. **Power on** — calls `alpaca_contrl.py power_on --sn <ALPACA_SN>`
4. **ADB poll loop** — polls `adb -s <DEVICE> get-state` every 3s up to `BOOT_TIMEOUT` (180s)
5. **Shell verify** — runs `adb shell echo "ok_<N>"` and reads `/proc/uptime` to confirm usable ADB

## Key Findings (from `sumary/adb_reboot_stability_results.md`)

- `adb reboot` is **unreliable** on this platform — device did not reconnect within 90s timeout.
- Alpaca hardware power cycle (`power_off` → 5s → `power_on`) is the **recommended** method — 20/20 pass rate.
- Typical boot-to-ADB time: **33s**; occasional slow cycle: ~45s (benign).
