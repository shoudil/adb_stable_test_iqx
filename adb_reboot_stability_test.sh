#!/bin/bash
# ADB Reboot Stability Test using Alpaca TAC
# Usage: ./adb_reboot_stability_test.sh [DEVICE_SERIAL] [ALPACA_SN] [ITERATIONS]

DEVICE="${1:-bbc3d4d2}"
ALPACA_SN="${2:-FTAGZXRO}"
ITERATIONS="${3:-10}"
BOOT_TIMEOUT=60

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG="/tmp/adb_reboot_stability_${TIMESTAMP}.log"
HTML="/tmp/adb_reboot_stability_${TIMESTAMP}.html"
FAIL_LOG="/tmp/adb_reboot_failures.log"
PASS=0; FAIL=0

# --- HTML helpers ---
html_init() {
    cat > "$HTML" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>ADB Reboot Stability Test — ${TIMESTAMP}</title>
<style>
  body { font-family: monospace; background:#1e1e1e; color:#d4d4d4; padding:24px; }
  h1 { color:#569cd6; }
  .meta { color:#9cdcfe; margin-bottom:16px; }
  table { border-collapse:collapse; width:100%; margin-top:16px; }
  th { background:#252526; color:#9cdcfe; padding:8px 12px; text-align:left; border-bottom:2px solid #3e3e42; }
  td { padding:7px 12px; border-bottom:1px solid #2d2d2d; }
  tr.pass td:first-child { border-left:4px solid #4ec9b0; }
  tr.fail td:first-child { border-left:4px solid #f44747; }
  .badge-pass { background:#0e4d3a; color:#4ec9b0; border-radius:4px; padding:2px 8px; }
  .badge-fail { background:#4d1010; color:#f44747; border-radius:4px; padding:2px 8px; }
  .summary { margin-top:24px; padding:12px 16px; background:#252526; border-radius:6px; }
  .summary-pass { color:#4ec9b0; }
  .summary-fail { color:#f44747; }
  .exit-banner { margin-top:16px; padding:10px 16px; background:#4d1010; color:#f44747; border-radius:6px; font-weight:bold; }
</style>
</head>
<body>
<h1>ADB Reboot Stability Test (Alpaca)</h1>
<div class="meta">
  <div>Device: <b>${DEVICE}</b> &nbsp;|&nbsp; Alpaca SN: <b>${ALPACA_SN}</b> &nbsp;|&nbsp; Iterations: <b>${ITERATIONS}</b></div>
  <div>Started: <b>$(date)</b></div>
  <div>Boot timeout: <b>${BOOT_TIMEOUT}s</b></div>
</div>
<table>
<tr><th>Cycle</th><th>Result</th><th>Online time</th><th>Uptime</th><th>Timestamp</th></tr>
EOF
}

html_row() {
    local cycle="$1" status="$2" online="$3" uptime="$4" ts="$5" note="$6"
    local cls badge
    if [ "$status" = "PASS" ]; then
        cls="pass"; badge='<span class="badge-pass">PASS</span>'
    else
        cls="fail"; badge='<span class="badge-fail">FAIL</span>'
    fi
    echo "<tr class=\"${cls}\"><td>${cycle}</td><td>${badge}</td><td>${online}</td><td>${uptime}</td><td>${ts}</td></tr>" >> "$HTML"
}

html_finish() {
    local extra_banner="$1"
    cat >> "$HTML" <<EOF
</table>
<div class="summary">
  <span class="summary-pass">PASS: ${PASS}</span> &nbsp;/&nbsp;
  <span class="summary-fail">FAIL: ${FAIL}</span> &nbsp;/&nbsp;
  Total: ${ITERATIONS}
  &nbsp;&nbsp;|&nbsp;&nbsp; Finished: $(date)
</div>
${extra_banner}
<div style="margin-top:12px;color:#6a9955;">Log: ${LOG}</div>
</body></html>
EOF
}

# --- Start ---
html_init
rm -f "$FAIL_LOG"

echo "ADB Reboot Stability Test (Alpaca) — device: $DEVICE  alpaca: $ALPACA_SN  iterations: $ITERATIONS" | tee "$LOG"
echo "Started: $(date)" | tee -a "$LOG"
echo "---" | tee -a "$LOG"

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
            MSG="[$TS2] cycle $i FAIL — ADB did not come online within ${BOOT_TIMEOUT}s, exiting"
            echo "$MSG" | tee -a "$LOG"
            echo "$MSG" >> "$FAIL_LOG"
            ((FAIL++))
            html_row "$i" "FAIL" ">=${BOOT_TIMEOUT}s" "—" "$TS2"
            echo "---" | tee -a "$LOG"
            echo "Result: $PASS/$ITERATIONS passed, $FAIL failed" | tee -a "$LOG"
            echo "Finished: $(date)" | tee -a "$LOG"
            html_finish '<div class="exit-banner">Test aborted: ADB timeout exceeded on cycle '"$i"'</div>'
            echo "Failure log: $FAIL_LOG"
            echo "Full log:    $LOG"
            echo "HTML report: $HTML"
            exit 1
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
            html_row "$i" "PASS" "${ONLINE_WAIT}s" "${UPTIME}s" "$TS2"
        else
            MSG="[$TS2] cycle $i FAIL — shell check returned: '$RESULT'"
            echo "$MSG" | tee -a "$LOG"
            echo "$MSG" >> "$FAIL_LOG"
            ((FAIL++))
            html_row "$i" "FAIL" "${ONLINE_WAIT}s" "—" "$TS2"
        fi
    fi
done

echo "---" | tee -a "$LOG"
echo "Result: $PASS/$ITERATIONS passed, $FAIL failed" | tee -a "$LOG"
echo "Finished: $(date)" | tee -a "$LOG"
html_finish ""
if [ -s "$FAIL_LOG" ]; then
    echo "Failure log: $FAIL_LOG"
else
    rm -f "$FAIL_LOG"
    echo "No failures."
fi
echo "Full log:    $LOG"
echo "HTML report: $HTML"
