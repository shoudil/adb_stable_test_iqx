# ADB Stability Issue Analysis

`dmesg_normal.txt` vs `dmesg_abnormal.txt` + `adb_service_status.txt`

---

## Part 1: USB Driver Comparison (`dmesg_normal.txt` vs `dmesg_abnormal.txt`)

### High-Level Outcome

|                      | Normal              | Abnormal                    |
|----------------------|---------------------|-----------------------------|
| ADB gadget connects? | Yes (~26s)          | Never (loops past 120s)     |
| Log ends at          | ~26s (post-connect) | ~120s (still looping)       |
| dwc3 error           | None                | Yes, at 26.667s             |

---

### 1. DWC3 ep0 Request Queue Failure — Root Cause

**Abnormal only** (line 1219):

```
[   26.667820] dwc3 a000000.usb: request 000000007b2681c4 was not queued to ep0out
```

This is the smoking gun. `ep0out` is the USB Control endpoint (OUT direction). The DWC3 USB Device Controller (Synopsys DesignWare USB3, used for the device-mode/gadget side — i.e., the ADB interface) failed to queue a setup-stage response. This typically means:

- The controller was not in the right state to accept the request (e.g., still resetting, PHY not ready, or a prior transfer was still pending)
- The host sent a SETUP packet, `adbd` tried to queue a response via FunctionFS, but the DWC3 driver rejected it

This causes the host to see no response → it resets the device → enumeration restarts.

---

### 2. FunctionFS Read Descriptors/Read Strings Retry Loop — The Symptom

Both logs show `adbd` registering its USB gadget via FunctionFS with this repeating pattern (every ~1 second):

```
read descriptors
bcdVersion must be 0x0100 ...
read strings
```

| Log      | Loop duration      | Outcome                                        |
|----------|--------------------|------------------------------------------------|
| Normal   | 16.6s → ~26.6s     | Loop stops → ADB connected                     |
| Abnormal | 16.0s → 120s+      | Loop never stops → ADB never connects          |

In the normal case, one of the `read descriptors` cycles completes and `adbd` successfully negotiates the USB gadget setup with the host. In the abnormal case, the DWC3 error at 26.667s poisons the control endpoint, and every subsequent enumeration attempt fails — `adbd` keeps retrying but can never complete the ep0 handshake.

---

### 3. USB Host-Side Initialization (xHCI) — Timing Delay

The abnormal log shows the entire USB host stack initializing ~200ms later:

| Event                        | Normal  | Abnormal | Delta   |
|------------------------------|---------|----------|---------|
| `xhci-hcd.1.auto` registered | 13.379s | 13.592s  | +213ms  |
| hub `1-0:1.0` found          | 13.380s | 13.593s  | +213ms  |
| hub `2-0:1.0` found          | 13.640s | 13.740s  | +100ms  |
| usb `1-1` enumerated         | 13.634s | 13.842s  | +208ms  |
| IRQ assignment               | 241, 242 | 243, 244 | different |

The different IRQ numbers (241/242 vs 243/244) indicate the xHCI driver bound in a different order relative to other drivers, which is consistent with the timing shift. This alone is not fatal but suggests something competed for initialization earlier in the boot.

---

### 4. Sequence Summary

**Normal boot (ADB succeeds):**

```
13.38s  xhci-hcd registers, hubs found
16.07s  FunctionFS: file system registered
16.62s  read descriptors / read strings (adbd begins gadget setup)
        ... ~10 retry cycles ~1s apart ...
~26.6s  [adbd connects -- loop stops, log goes quiet]
```

**Abnormal boot (ADB fails):**

```
13.59s  xhci-hcd registers (213ms late), hubs found
16.07s  FunctionFS: file system registered
16.06s  read descriptors / read strings (adbd begins gadget setup)
        ... retry cycles ~1s apart ...
26.67s  *** dwc3 a000000.usb: request was not queued to ep0out ***
        ... retry cycles continue every ~1s, no recovery ...
120s+   [ADB never connects -- captured 100+ failed cycles]
```

---

## Part 2: ADB Service Status Analysis (`adb_service_status.txt`)

### Normal Case

- **Service uptime at capture:** 16 seconds (freshly connected)
- **CPU used:** 438ms
- **Tasks:** 6 threads

**Event sequence:**

```
17:04:15  UsbFfsConnection being destroyed        <- cleanup from prior attempt
17:04:15  UsbFfsConnection destroyed
17:04:16  opening control endpoint /dev/usb-ffs/adb/ep0
17:04:16  UsbFfsConnection constructed
17:04:16  android-gadget-start: Binding Gadget to UDC: a000000.usb (super-speed-plus)
17:04:16  USB event: FUNCTIONFS_BIND              <- kernel confirms gadget is active
17:04:16  systemd: Started Android Debug Bridge
17:04:16  USB event: FUNCTIONFS_ENABLE            <- host enumerated and enabled interface
17:04:17  UsbFfs: already offline                 <- waiting for host to open ADB transport
17:04:17  authentication not required
```

**UDC state:**

```
cat /sys/kernel/config/usb_gadget/adb/UDC
a000000.usb   <- bound
```

The gadget is bound to DWC3 controller `a000000.usb`. The host completed USB enumeration and enabled the ADB interface (`FUNCTIONFS_ENABLE`). ADB is ready.

---

### Abnormal Case

- **Service uptime at capture:** 3 hours 22 minutes (started 01:20:14, captured ~04:42)
- **CPU used:** 5 min 35.858s — `adbd` has been burning CPU in a retry loop for hours
- **Tasks:** 55 (vs. 6 in normal — accumulated failed connection attempt threads)

**Event sequence (repeating loop at 04:42):**

```
04:42:28  UsbFfsConnection being destroyed
04:42:28  opening control endpoint /dev/usb-ffs/adb/ep0
04:42:28  UsbFfsConnection constructed
04:42:29  *** timed out while waiting for FUNCTIONFS_BIND, trying again ***
04:42:29  connection terminated: monitor thread finished
04:42:29  UsbFfs: already offline
04:42:29  destroying transport UsbFfs
04:42:29  UsbFfsConnection being destroyed
04:42:29  opening control endpoint /dev/usb-ffs/adb/ep0   <- retry begins immediately
04:42:29  UsbFfsConnection constructed
          (loop repeats every ~1s)
```

**UDC state:**

```
cat /sys/kernel/config/usb_gadget/adb/UDC
                        <- empty -- gadget is NOT bound to any controller
```

`FUNCTIONFS_BIND` is never received, meaning the USB gadget function never gets registered with the DWC3 controller. `android-gadget-start` is a one-shot `ExecStartPost` — it ran once at service start (exit status 0/SUCCESS), but the binding has since been lost and is never re-attempted.

---

## Part 3: Combined Root Cause

Putting the dmesg and service status together, here is the exact failure chain:

```
Boot
 |
 +--[~16s]  adbd starts, android-gadget-start runs:
 |           writes "a000000.usb" -> /sys/kernel/config/usb_gadget/adb/UDC
 |           gadget is bound, adbd begins FunctionFS setup cycle
 |
 +--[16-26s] adbd: repeated "read descriptors / read strings" -- retrying enum
 |           (host is sending USB SETUP packets, DWC3 handles ep0)
 |
 +--[26.667s] *** dwc3 a000000.usb: request was not queued to ep0out ***
 |             DWC3 gadget-mode controller rejects an ep0 (control endpoint) request
 |             -> DWC3 gadget driver tears down the UDC binding
 |             -> /sys/kernel/config/usb_gadget/adb/UDC becomes EMPTY
 |
 +--[26.67s+] adbd: FUNCTIONFS_BIND timeout on each attempt (UDC is empty,
 |             gadget has no controller -- kernel can't deliver BIND event)
 |             -> destroy -> open ep0 -> construct -> timeout -> loop
 |
 +--[3h22min] adbd still looping every ~1s
               UDC file still empty
               ADB never available
```

**Why the normal case works:**
The DWC3 ep0 request is successfully queued, the host completes `SET_CONFIGURATION`, the kernel fires `FUNCTIONFS_BIND` then `FUNCTIONFS_ENABLE`, and `adbd` transitions to the connected state.

**Why the abnormal case never recovers:**

1. The DWC3 ep0 error unbinds the gadget from the UDC.
2. `android-gadget-start` (which re-binds the gadget) is a one-shot script — it only runs as `ExecStartPost` at service start. It is never re-triggered after the UDC drops.
3. `adbd`'s own retry loop only re-opens `/dev/usb-ffs/adb/ep0` and waits for `FUNCTIONFS_BIND` — but `FUNCTIONFS_BIND` requires the gadget to be bound to a UDC, which requires `android-gadget-start` to run again.
4. Neither `adbd` nor systemd has a recovery mechanism for this state.

---

## Part 4: Fix / Mitigation Recommendations

### Short-term (workaround in test script)

After a failed ADB reconnection, SSH into the device and re-run `android-gadget-start` manually (or call it via a watchdog). This re-writes the UDC file and restores the binding.

### Proper Fix — systemd Service Hardening

Add a `FUNCTIONFS_BIND` watchdog to trigger `android-gadget-start` if UDC drops:

```ini
# /usr/lib/systemd/system/android-tools-adbd.service.d/udc-watchdog.conf
[Service]
Restart=on-failure
RestartSec=2
ExecStartPost=/bin/sh -c 'echo a000000.usb > /sys/kernel/config/usb_gadget/adb/UDC || true'
```

Or a dedicated udev rule that triggers `android-gadget-start` when the UDC sysfs attribute becomes empty.

### Root Fix — DWC3 Kernel Driver

Investigate and fix the "request not queued to ep0out" condition in the DWC3 gadget driver. This is a race between a host USB RESET (or `SET_ADDRESS` / `SET_CONFIGURATION`) and a pending ep0 transfer. Upstream DWC3 patches worth checking: commits in `drivers/usb/dwc3/gadget.c` related to `dwc3_gadget_ep0_queue` error handling and reset recovery.
