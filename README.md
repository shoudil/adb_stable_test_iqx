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

Logs are written to `/tmp/adb_reboot_stability_<timestamp>.log`. If any cycle fails, a summary is also written to `/tmp/adb_reboot_failures.log`.

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

Tested on **X1E80100 EVK** (2026-05-17):

| Method | Iterations | Passed | Notes |
|---|---|---|---|
| `adb reboot` | 1 | 0 | Device did not reconnect within 90s — **unreliable** |
| Alpaca power cycle | 20 | 20 | Stable; typical boot-to-ADB ~33s, max ~45s |

See `sumary/adb_reboot_stability_results.md` for per-cycle timing details.
