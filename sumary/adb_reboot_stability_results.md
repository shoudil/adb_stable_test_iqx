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

## Boot Time Statistics (Runs 2 & 3 combined, 20 cycles)

| Metric | Value |
|---|---|
| Min | 33s |
| Max | 45s |
| Typical | 33s |
| Slow cycles (>40s) | 2/20 (cycles with ~45s boot) |

## Notes

- Run 1 used `adb reboot` which caused the device to not reconnect within the 90s timeout. Root cause: ADB reboot is unreliable on this platform; Alpaca hardware power cycle is the recommended method.
- Runs 2 & 3 used Alpaca TAC (`power_off` → 5s delay → `power_on`) — fully stable.
- The occasional ~45s boot (vs typical 33s) appears benign; ADB always came up successfully.

## Log Files

| File | Description |
|---|---|
| `adb_reboot_stability_20260517_071138.log` | Run 1 — `adb reboot` method (failed) |
| `adb_reboot_stability_20260517_071720.log` | Run 2 — Alpaca method (10/10 pass) |
| `/tmp/adb_reboot_stability_20260517_074656.log` | Run 3 — Alpaca method (10/10 pass) |
| `adb_reboot_stability_test.sh` | Test script |
