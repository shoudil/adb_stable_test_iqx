# adb_stable_test_iqx

ADB stability test for Qualcomm platforms using Alpaca TAC hardware power cycling.

Validates that a device reliably reconnects over ADB after repeated hardware power cycles, using an Alpaca TAC unit to control device power rather than `adb reboot` (which is unreliable on some Qualcomm platforms).

## Requirements

- `adb` on PATH
- Alpaca TAC unit connected via USB
- Alpaca SDK installed at `/opt/qcom/Alpaca/python` (provides `TACDev`)

## Usage

```bash
./adb_reboot_stability_test.sh [DEVICE_SERIAL] [ALPACA_SN] [ITERATIONS]
```

| Argument | Default | Description |
|---|---|---|
| `DEVICE_SERIAL` | `bbc3d4d2` | ADB device serial number |
| `ALPACA_SN` | `FTAGZXRO` | Alpaca TAC unit serial number |
| `ITERATIONS` | `10` | Number of power-cycle iterations |

Example — 50-cycle run on a specific device:
```bash
./adb_reboot_stability_test.sh abc12345 FTAGZXRO 50
```

Each run writes two output files:

| File | Description |
|---|---|
| `/tmp/adb_reboot_stability_<timestamp>.log` | Full text log of every cycle |
| `/tmp/adb_reboot_stability_<timestamp>.html` | Per-cycle HTML report with PASS/FAIL badges |
| `/tmp/adb_reboot_failures.log` | Failure-only log (written only when failures occur) |

The test exits immediately if ADB does not reconnect within the boot timeout (60 s).

## Alpaca TAC Control

`tools/alpaca_contrl.py` wraps the Alpaca TAC SDK and can be used independently:

```bash
# List connected TAC devices
python3 tools/alpaca_contrl.py list

# Power cycle a device
python3 tools/alpaca_contrl.py power_off --sn FTAGZXRO
python3 tools/alpaca_contrl.py power_on  --sn FTAGZXRO

# Boot device into EDL mode
python3 tools/alpaca_contrl.py edl --sn FTAGZXRO --method button   # default
python3 tools/alpaca_contrl.py edl --sn FTAGZXRO --method pin      # EDL pin + battery power-cycle
```

## Results

Tested on **X1E80100 EVK** (2026-05-17, device `bbc3d4d2`, Alpaca SN `FTAGZXRO`):

| Log | Time | Method | Cycles | Pass | Fail | Pass Rate | Notes |
|---|---|---|---|---|---|---|---|
| `20260517_071138` | 07:11 | `adb reboot` | 1 / 10 | 0 | 1 | 0% | Aborted — device never reconnected within 90 s |
| `20260517_071720` | 07:17 | Alpaca TAC | 10 / 10 | 10 | 0 | **100%** | Avg online 35.7 s |
| `20260517_074656` | 07:46 | Alpaca TAC | 10 / 10 | 10 | 0 | **100%** | Avg online 34.2 s |
| `20260517_174045` | 17:40 | Alpaca TAC | 20 / 20 | 16 | 4 | 80% | 4 ADB timeouts (>180 s); cycles 16–17 consecutive |

**Overall Alpaca TAC: 36 / 40 cycles passed (90%) across three runs.**

### Boot timing (Alpaca TAC passing cycles)

| Bucket | Observed | Meaning |
|---|---|---|
| 33 s | Typical | Normal boot |
| 36 s | Occasional | Slightly slower boot |
| 45 s | Rare | Slow cycle — still within timeout, benign |
| > 60 s | 4 occurrences | ADB timeout — test exits immediately |

### Failure detail (Run 4 — `20260517_174045`)

| Cycle | Timestamp | Failure |
|---|---|---|
| 6 | 17:47:57 | ADB did not come online within 180 s |
| 9 | 17:52:45 | ADB did not come online within 180 s |
| 16 | 18:00:39 | ADB did not come online within 180 s |
| 17 | 18:03:53 | ADB did not come online within 180 s (consecutive) |

Device recovered on the next cycle in all four cases.

See `sumary/adb_reboot_stability_summary.html` for the full aggregated HTML report.
