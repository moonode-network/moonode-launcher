# Setup Script Troubleshooting

Quick reference for the most common things that go wrong when running
`setup-moonode-launcher.sh <STICK_IP>` against a fresh Fire TV stick.
Each section ends with a one-line **fix**.

---

## 1. `adb connect` hangs forever

You typed `adb connect 192.168.5.165:5555` and nothing happens for 60+
seconds. No `connected` message, no error, no popup on the TV.

### Cause

Either:
- **ADB debugging is not enabled** on the stick yet, or
- **The Mac and the stick are on networks that can't reach each other**
  (most common cause — see Section 2 below for the Mac-side variant).

### Diagnose

```bash
# Can the Mac even reach the stick at all?
ping -c 3 -W 1 192.168.5.165
```

- ✅ Replies → ADB just isn't enabled yet → go to Section 5 below
- ❌ `Request timeout` → it's a network/routing problem → go to Section 2 below

---

## 2. Mac on Ethernet, stick on Wi-Fi (router isolates them)

Most consumer routers (Eero, Google Nest Wi-Fi, ISP-supplied gateways,
mesh systems with default settings) put **wired** and **wireless** clients
in separate broadcast domains. Even though they share the same `192.168.x.x`
subnet, traffic between them is blocked. ARP works one-way (you see the
stick's MAC) but actual pings/TCP do not.

### Fingerprint

```
$ arp -a | grep 192.168.5
i-zeiv      (192.168.5.128)  at 5c:e9:1e:8c:c8:e1  ... [ethernet]
?           (192.168.5.165)  at (incomplete)        ... [ethernet]   ← stick
```

`(incomplete)` on the stick line is the smoking gun — the Mac knows it
should exist but the stick is not answering its ARPs.

### Fix

**Turn the Mac's Wi-Fi on and join the same SSID as the stick.**

```bash
# Bring Wi-Fi up
networksetup -setairportpower en0 on

# (Optional) join an SSID from the command line
networksetup -setairportnetwork en0 "YOUR_SSID" "YOUR_PASSWORD"

# Confirm
ifconfig en0 | grep "inet "
ping -c 3 192.168.5.165
```

The Wi-Fi interface varies by Mac model. To find yours:

```bash
networksetup -listallhardwareports | grep -A 1 "Wi-Fi"
```

On Apple Silicon MacBooks it's usually `en0`. On Intel iMacs it's often
`en1`. Once `ping` succeeds, ADB will connect instantly.

---

## 3. `adb devices` shows `unauthorized`

```
$ adb devices
List of devices attached
192.168.5.165:5555    unauthorized
```

### Cause

The stick is waiting for you to approve this computer's RSA key.

### Fix

**Look at the TV screen.** A dialog *"Allow USB debugging? Always allow
from this computer"* is waiting. Check the box, select **OK** with the
remote, then re-check:

```bash
adb devices
# 192.168.5.165:5555    device       ← correct
```

If the popup never appeared:
- Press HOME on the remote to wake the screen, then run
  `adb connect 192.168.5.165:5555` again to re-trigger the popup
- If the stick was rebooted, the trust is reset — popup re-appears next connect

---

## 4. `adb devices` shows `offline`

### Cause

ADB daemon got into a bad state, or the stick's network changed (DHCP
renew, Wi-Fi roam, etc).

### Fix

```bash
adb kill-server
adb start-server
adb connect 192.168.5.165:5555
```

---

## 5. ADB debugging is not enabled on the stick (fresh out of the box)

Fire OS ships with developer options hidden.

### Fix on the stick (one-time)

1. **Settings → My Fire TV → About**
2. Highlight the device name row (e.g. *"Fire TV Stick 4K Plus"*)
3. Press **OK 7 times** rapidly → you'll see *"You are now a developer"*
4. Back out to **Settings → My Fire TV → Developer options**
5. Turn **ADB debugging → ON**
6. Turn **Apps from Unknown Sources → ON**
7. Note the stick's IP: **Settings → My Fire TV → About → Network**

Then on the Mac:

```bash
adb connect <STICK_IP>:5555
# Approve the popup on the TV
adb devices
```

---

## 6. Stick's IP changed

DHCP leases expire. After a reboot or extended power-off, a Fire TV may
come back with a different IP.

### Find the new IP

On the stick: **Settings → My Fire TV → About → Network → IP Address**

Or scan the LAN from the Mac:

```bash
# Replace 192.168.5 with your subnet
for i in $(seq 1 254); do
  (ping -c 1 -W 1 192.168.5.$i >/dev/null 2>&1 && echo "alive: 192.168.5.$i") &
done; wait

# Then look for the Amazon MAC (starts with 4c:60:ad, fc:65:de, etc.)
arp -a | grep -iE "(4c:60:ad|fc:65:de|5c:cf:7f|50:dc:e7|f0:27:2d)"
```

To make this stable, assign the stick a **DHCP reservation** in your
router admin panel. Tie the stick's MAC to a fixed IP so the setup
script always finds it at the same address.

---

## 7. `Failed to install APK` — `INSTALL_FAILED_INSUFFICIENT_STORAGE`

The stick is full of cached Amazon junk.

### Fix

```bash
# Clear caches across all packages
adb shell pm trim-caches 999999999999

# Or factory-reset the stick from Settings → My Fire TV → Reset
```

---

## 8. `Failed to install APK` — `INSTALL_FAILED_USER_RESTRICTED`

### Fix

On the stick: **Settings → My Fire TV → Developer options → Apps from
Unknown Sources → ON** (for the Moonode Launcher app specifically if
prompted).

---

## 9. `Failed to install APK` — `INSTALL_FAILED_MISSING_SHARED_LIBRARY`

The stick lacks the `android.software.leanback` system feature (some
Fire OS variants).

### Fix

This is already handled in our `AndroidManifest.xml`
(`leanback` is marked `required="false"`). If you still hit this, you're
running an old APK. Rebuild:

```bash
cd /Users/zeiv/Desktop/infrastructure/moonode-launcher
flutter build apk --release
```

---

## 10. `wm overscan: Unknown command` warning

You'll see this in the script output on Fire OS 8:

```
Unknown command: overscan
```

### Cause

Amazon removed the `wm overscan` API in Fire OS 8 (Android 11). The
display has used 100% of the screen by default since Fire OS 6 anyway, so
the command was already a no-op.

### Fix

**No action needed.** It's a benign warning. The script otherwise completes
successfully and the display is correct.

---

## 11. HOME Guardian was disabled after a reboot / APK reinstall

Fire OS occasionally wipes the `enabled_accessibility_services` list.

### Auto-fix (already implemented)

The launcher self-heals on every cold start using the `WRITE_SECURE_SETTINGS`
permission granted by this script. You should never see this manually.

### Manual fallback

```bash
adb -s <STICK_IP>:5555 shell settings put secure enabled_accessibility_services \
  com.moonode.launcher/com.moonode.launcher.HomeHijackService
adb -s <STICK_IP>:5555 shell settings put secure accessibility_enabled 1
```

---

## 12. Energy Saver 4-hour auto-off still happens

The script tries to disable this via `stay_on_while_plugged_in=7` plus
several Amazon-internal keys, but on some Fire OS 8 builds the toggle is
gated behind the on-screen UI only.

### Fix on the stick (one-time)

**Settings → Preferences → Power → Energy Saver → Off**

(On some builds the menu is **Settings → Display & Sounds → Energy Saver**.)

---

## 13. Restoring the stick to factory state

If you ever need to give the stick back to the customer with the Amazon
launcher:

```bash
DEV=<STICK_IP>:5555
adb -s $DEV uninstall com.moonode.launcher
adb -s $DEV shell pm enable com.amazon.tv.launcher
adb -s $DEV shell pm enable com.amazon.tv.forcedotaupdater.v2
adb -s $DEV shell settings put global captive_portal_mode 1
adb -s $DEV shell settings put system screen_off_timeout 600000
```

Or the nuclear option: **Settings → My Fire TV → Reset to Factory Defaults**.

---

## Quick "is the install healthy?" one-liner

```bash
DEV=<STICK_IP>:5555
echo "Launcher version: $(adb -s $DEV shell dumpsys package com.moonode.launcher | grep versionName | head -1 | tr -d '\r')"
echo "WRITE_SECURE_SETTINGS: $(adb -s $DEV shell dumpsys package com.moonode.launcher | grep 'WRITE_SECURE_SETTINGS: granted')"
echo "HOME Guardian service: $(adb -s $DEV shell settings get secure enabled_accessibility_services | tr -d '\r')"
echo "Screen-off timeout: $(adb -s $DEV shell settings get system screen_off_timeout | tr -d '\r') (want 2147483647)"
echo "stay_on_while_plugged_in: $(adb -s $DEV shell settings get global stay_on_while_plugged_in | tr -d '\r') (want 7)"
echo "Free RAM: $(adb -s $DEV shell cat /proc/meminfo | grep MemAvailable | tr -d '\r')"
```

A healthy install on a Fire TV Stick 4K Plus looks like:

```
Launcher version:     versionName=1.0.16
WRITE_SECURE_SETTINGS: granted=true
HOME Guardian service: com.moonode.launcher/com.moonode.launcher.HomeHijackService
Screen-off timeout:   2147483647 (want 2147483647)
stay_on_while_plugged_in: 7 (want 7)
Free RAM:             MemAvailable:     540708 kB
```
