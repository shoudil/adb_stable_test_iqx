# ADB Reboot Stability Test Results

## Device Info

| Field | Value |
|---|---|
| Device Serial | `bbc3d4d2` |
| Alpaca TAC SN | `FTAGZXRO` |
| Alpaca Firmware | Alpaca 6.1.0 / TAC 8.0.0 |
| Platform | X1E80100 EVK |
| Date | 2026-05-17 |

## Summary

| Run | Method | Iterations | Passed | Failed | Result |
|---|---|---|---|---|---|
| 1 | `adb reboot` | 1 | 0 | 1 | FAIL — device did not come back online within 90s |
| 2 | Alpaca power_off/power_on | 10 | 10 | 0 | PASS |
| 3 | Alpaca power_off/power_on | 10 | 10 | 0 | PASS |
| 4 | Alpaca power_off/power_on | 20 | 16 | 4 | PARTIAL PASS — 4 cycles timed out (180s); cycles 6, 9, 16, 17 |

## Run 2 Detail (07:17 – 07:25 CST)

| Cycle | Boot-to-ADB | Uptime at ADB | Result |
|---|---|---|---|
| 1 | 33s | 28.35s | PASS |
| 2 | 33s | 28.34s | PASS |
| 3 | 36s | 31.37s | PASS |
| 4 | 36s | 31.29s | PASS |
| 5 | 33s | 28.33s | PASS |
| 6 | 33s | 28.25s | PASS |
| 7 | 36s | 31.28s | PASS |
| 8 | 33s | 28.33s | PASS |
| 9 | 45s | 40.43s | PASS |
| 10 | 33s | 28.32s | PASS |

## Run 3 Detail (07:46 – 07:54 CST)

| Cycle | Boot-to-ADB | Uptime at ADB | Result |
|---|---|---|---|
| 1 | 33s | 28.37s | PASS |
| 2 | 33s | 28.35s | PASS |
| 3 | 33s | 28.35s | PASS |
| 4 | 33s | 28.26s | PASS |
| 5 | 33s | 28.34s | PASS |
| 6 | 45s | 40.45s | PASS |
| 7 | 36s | 31.37s | PASS |
| 8 | 33s | 28.35s | PASS |
| 9 | 36s | 31.38s | PASS |
| 10 | 33s | 28.34s | PASS |

## Run 4 Detail (17:40 – 18:06 CST)

| Cycle | Boot-to-ADB | Uptime at ADB | Result |
|---|---|---|---|
| 1 | 33s | 28.24s | PASS |
| 2 | 33s | 28.32s | PASS |
| 3 | 33s | 28.29s | PASS |
| 4 | 36s | 31.37s | PASS |
| 5 | 36s | 31.38s | PASS |
| 6 | — | — | FAIL — timed out (180s) |
| 7 | 33s | 28.37s | PASS |
| 8 | 33s | 28.28s | PASS |
| 9 | — | — | FAIL — timed out (180s) |
| 10 | 33s | 28.36s | PASS |
| 11 | 33s | 28.36s | PASS |
| 12 | 33s | 28.37s | PASS |
| 13 | 36s | 31.38s | PASS |
| 14 | 33s | 28.35s | PASS |
| 15 | 33s | 28.36s | PASS |
| 16 | — | — | FAIL — timed out (180s) |
| 17 | — | — | FAIL — timed out (180s) |
| 18 | 33s | 28.36s | PASS |
| 19 | 33s | 28.36s | PASS |
| 20 | 36s | 31.37s | PASS |

## Boot Time Statistics (Runs 2–4, 36 successful cycles)

| Metric | Value |
|---|---|
| Min | 33s |
| Max | 45s |
| Typical | 33s |
| Slow cycles (36s) | 8/36 |
| Slow cycles (45s) | 2/36 (both in runs 2 & 3) |
| Failed cycles (timeout >180s) | 4/20 in run 4 (first failures observed with Alpaca method) |

## Notes

- Run 1 used `adb reboot` which caused the device to not reconnect within the 90s timeout. Root cause: ADB reboot is unreliable on this platform; Alpaca hardware power cycle is the recommended method.
- Runs 2 & 3 used Alpaca TAC (`power_off` → 5s delay → `power_on`) — fully stable.
- The occasional ~45s boot (vs typical 33s) appears benign; ADB always came up successfully.
- Run 4 used the same Alpaca method with 20 iterations and recorded 4 failures (cycles 6, 9, 16, 17 all timed out at 180s). This is the first time the Alpaca method has shown failures and suggests the DWC3/UDC instability can also manifest during hardware power cycles, not only `adb reboot`.

## Root Cause Analysis

See **[analysis.md](analysis.md)** for the full dmesg + service status analysis, covering:

- DWC3 `ep0out` request queue failure (the smoking gun)
- FunctionFS retry loop behaviour (normal vs abnormal)
- xHCI timing delta between normal and abnormal boots
- Combined failure chain and why the device never recovers without intervention
- Fix / mitigation recommendations (workaround, systemd hardening, DWC3 kernel fix)

## Test Scripts

| Script | Method | Description |
|---|---|---|
| `adb_reboot_stability_test.sh` | Alpaca power cycle | Primary stability test — `power_off` → 5s → `power_on`; recommended method |
| `adb_reboot_only_test.sh` | `adb reboot` only | Software-reboot-only variant; no recovery; known unreliable on X1E80100 EVK |
| `adb_reboot_with_recovery_test.sh` | `adb reboot` + Alpaca recovery | Hybrid: issues `adb reboot`, detects cDSP RPC Daemon timeout in logcat, triggers Alpaca recovery on failure |

## Log Files

| File | Description |
|---|---|
| `adb_reboot_stability_20260517_071138.log` | Run 1 — `adb reboot` method (failed) |
| `adb_reboot_stability_20260517_071720.log` | Run 2 — Alpaca method (10/10 pass) |
| `/tmp/adb_reboot_stability_20260517_074656.log` | Run 3 — Alpaca method (10/10 pass) |
| `adb_reboot_stability_20260517_174045.log` | Run 4 — Alpaca method (16/20 pass, 4 timeouts) |
| `logs/adb_stable_issue.txt` | Raw `systemctl status android-tools-adbd` capture from the abnormal (stuck) case |
| `analysis.md` | Full root cause analysis (dmesg + service status) |
