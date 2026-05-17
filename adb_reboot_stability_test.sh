#!/bin/bash
# ADB Reboot Stability Test using Alpaca TAC
# Usage: ./adb_reboot_stability_test.sh [DEVICE_SERIAL] [ALPACA_SN] [ITERATIONS]

DEVICE="${1:-bbc3d4d2}"
ALPACA_SN="${2:-FTAGZXRO}"
ITERATIONS="${3:-10}"
BOOT_TIMEOUT=180

LOG="/tmp/adb_reboot_stability_$(date +%Y%m%d_%H%M%S).log"
FAIL_LOG="/tmp/adb_reboot_failures.log"
PASS=0; FAIL=0

echo "ADB Reboot Stability Test (Alpaca) — device: $DEVICE  alpaca: $ALPACA_SN  iterations: $ITERATIONS" | tee "$LOG"
echo "Started: $(date)" | tee -a "$LOG"
echo "---" | tee -a "$LOG"

rm -f "$FAIL_LOG"

for i in $(seq 1 $ITERATIONS); do
    TS=$(date +%H:%M:%S)
    echo "[$TS] === Cycle $i/$ITERATIONS ===" | tee -a "$LOG"

    # Power off via Alpaca
    echo "  Power off..." | tee -a "$LOG"
    python3 tools/alpaca_contrl.py power_off --sn "$ALPACA_SN" 2>&1 | tee -a "$LOG"
    sleep 5

    # Power on via Alpaca
    echo "  Power on..." | tee -a "$LOG"
    python3 tools/alpaca_contrl.py power_on --sn "$ALPACA_SN" 2>&1 | tee -a "$LOG"

    # Wait for ADB to come back online
    echo "  Waiting for ADB online (max ${BOOT_TIMEOUT}s)..." | tee -a "$LOG"
    ONLINE_WAIT=0
    while true; do
        STATE=$(adb -s "$DEVICE" get-state 2>/dev/null)
        if [ "$STATE" = "device" ]; then break; fi
        sleep 3; ONLINE_WAIT=$((ONLINE_WAIT+3))
        if [ $ONLINE_WAIT -ge $BOOT_TIMEOUT ]; then
            TS2=$(date +%H:%M:%S)
            MSG="[$TS2] cycle $i FAIL — ADB did not come online within ${BOOT_TIMEOUT}s"
            echo "$MSG" | tee -a "$LOG"
            echo "$MSG" >> "$FAIL_LOG"
            ((FAIL++))
            break
        fi
    done

    # Verify shell
    STATE=$(adb -s "$DEVICE" get-state 2>/dev/null)
    TS2=$(date +%H:%M:%S)
    if [ "$STATE" = "device" ]; then
        RESULT=$(adb -s "$DEVICE" shell echo "ok_$i" 2>&1)
        UPTIME=$(adb -s "$DEVICE" shell cat /proc/uptime 2>/dev/null | awk '{print $1}')
        if [ "$RESULT" = "ok_$i" ]; then
            echo "[$TS2] cycle $i PASS — online in ${ONLINE_WAIT}s, uptime=${UPTIME}s" | tee -a "$LOG"
            ((PASS++))
        else
            MSG="[$TS2] cycle $i FAIL — shell check returned: '$RESULT'"
            echo "$MSG" | tee -a "$LOG"
            echo "$MSG" >> "$FAIL_LOG"
            ((FAIL++))
        fi
    fi
done

echo "---" | tee -a "$LOG"
echo "Result: $PASS/$ITERATIONS passed, $FAIL failed" | tee -a "$LOG"
echo "Finished: $(date)" | tee -a "$LOG"
if [ -s "$FAIL_LOG" ]; then
    echo "Failure log: $FAIL_LOG"
else
    rm -f "$FAIL_LOG"
    echo "No failures."
fi
echo "Full log: $LOG"
