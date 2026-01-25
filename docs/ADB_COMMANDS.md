# ADB Commands Reference for Moonode Launcher

Quick reference for all ADB commands used to set up and manage Moonode Launcher on Android TV devices.

## Connection

### Connect via WiFi
```bash
# Connect to device (default port 5555)
adb connect 192.168.100.5:5555

# Connect with custom port (for Wireless Debugging on Android 11+)
adb connect 192.168.100.5:12345

# Disconnect all devices
adb disconnect

# Disconnect specific device
adb disconnect 192.168.100.5:5555
```

### Enable WiFi ADB (requires USB first)
```bash
# Connect device via USB, then run:
adb tcpip 5555

# Now disconnect USB and connect via WiFi
adb connect <DEVICE_IP>:5555
```

### List Connected Devices
```bash
adb devices
```

### Target Specific Device (when multiple connected)
```bash
# Use -s flag with device serial
adb -s 192.168.100.5:5555 shell <command>
adb -s 192.168.100.5:5555 install app.apk
```

## App Installation

### Install APK
```bash
# Install (or reinstall)
adb install -r moonode-launcher.apk

# Install to specific device
adb -s 192.168.100.5:5555 install -r moonode-launcher.apk
```

### Uninstall App
```bash
adb uninstall com.moonode.launcher
```

### List Installed Packages
```bash
adb shell pm list packages | grep moonode
```

## Launcher Configuration

### Disable Default Launchers
```bash
# Google TV Launcher
adb shell pm disable-user --user 0 com.google.android.apps.tv.launcherx

# Android TV Launcher
adb shell pm disable-user --user 0 com.google.android.tvlauncher

# Older Android TV Launcher
adb shell pm disable-user --user 0 com.google.android.leanbacklauncher

# Google TV Setup/Fallback
adb shell pm disable-user --user 0 com.google.android.tungsten.setupwraith

# Fire TV Launcher
adb shell pm disable-user --user 0 com.amazon.tv.launcher
```

### Re-enable Default Launchers (Restore)
```bash
adb shell pm enable com.google.android.apps.tv.launcherx
adb shell pm enable com.google.android.tungsten.setupwraith
adb shell pm enable com.google.android.tvlauncher
```

### Detect Current Launcher
```bash
adb shell cmd package resolve-activity -a android.intent.action.MAIN -c android.intent.category.HOME
```

## Display Settings

### Reset Overscan (Full Screen - No Cropping)
```bash
# Set overscan to 0 on all sides (left, top, right, bottom)
adb shell wm overscan 0,0,0,0

# Or reset to default
adb shell wm overscan reset
```

### Reset Display Density
```bash
adb shell wm density reset
```

### Get Current Display Size
```bash
adb shell wm size
```

### Get Current Display Density
```bash
adb shell wm density
```

## Network & Offline Mode

### Disable Captive Portal Detection (No "WiFi has no internet" warnings)
```bash
adb shell settings put global captive_portal_mode 0
adb shell settings put global captive_portal_detection_enabled 0
adb shell settings put global wifi_watchdog_on 0
```

### Restore Captive Portal Detection
```bash
adb shell settings put global captive_portal_mode 1
adb shell settings put global captive_portal_detection_enabled 1
adb shell settings put global wifi_watchdog_on 1
```

## Kiosk Mode Settings

### Screen Always On (Never Sleep)
```bash
# Set timeout to max value (~68 years)
adb shell settings put system screen_off_timeout 2147483647
```

### Restore Normal Screen Timeout
```bash
# Set to 5 minutes (300000ms)
adb shell settings put system screen_off_timeout 300000
```

## Device Information

### Get Device Model
```bash
adb shell getprop ro.product.model
```

### Get Android Version
```bash
adb shell getprop ro.build.version.release
```

### Get Device IP Address
```bash
adb shell ip addr show wlan0 | grep "inet "
```

### Get All System Properties
```bash
adb shell getprop
```

## Debugging

### View Logs (Logcat)
```bash
# All logs
adb logcat

# Filter by tag
adb logcat -s MoonodeLauncher

# Filter by priority (V=Verbose, D=Debug, I=Info, W=Warn, E=Error)
adb logcat *:E

# Clear logs
adb logcat -c
```

### Take Screenshot
```bash
adb shell screencap /sdcard/screenshot.png
adb pull /sdcard/screenshot.png ./screenshot.png
```

### Record Screen
```bash
adb shell screenrecord /sdcard/video.mp4
# Press Ctrl+C to stop
adb pull /sdcard/video.mp4 ./video.mp4
```

## ADB Server Management

### Start/Stop ADB Server
```bash
adb start-server
adb kill-server
```

### Fix ADB Permissions (macOS)
```bash
# If ADB fails with "Operation not permitted"
sudo adb start-server

# Or fix ownership
sudo chown -R $(whoami) ~/Library/Android/sdk/platform-tools
```

## Complete Setup Command Sequence

```bash
# 1. Connect to device
adb connect 192.168.100.5:5555

# 2. Install Moonode Launcher
adb install -r moonode-launcher.apk

# 3. Disable default launchers
adb shell pm disable-user --user 0 com.google.android.apps.tv.launcherx
adb shell pm disable-user --user 0 com.google.android.tvlauncher

# 4. Configure offline mode (no "no internet" warnings)
adb shell settings put global captive_portal_mode 0
adb shell settings put global captive_portal_detection_enabled 0

# 5. Configure kiosk mode (always on)
adb shell settings put system screen_off_timeout 2147483647

# 6. Reset display (full screen)
adb shell wm overscan 0,0,0,0
adb shell wm density reset

# 7. Verify installation
adb shell pm list packages | grep moonode
```

## Troubleshooting

### "more than one device/emulator"
```bash
# Disconnect all and reconnect to specific device
adb disconnect
adb connect 192.168.100.5:5555
```

### "Connection refused"
- Enable Developer Options on device
- Enable USB Debugging
- Enable Network Debugging / Wireless ADB
- Check device is on same network
- Try connecting via USB first, then `adb tcpip 5555`

### "unauthorized"
- Check TV screen for authorization dialog
- Accept "Allow USB debugging from this computer"

### ADB not found
```bash
# Add to PATH (add to ~/.zshrc or ~/.bashrc)
export PATH=$PATH:~/Library/Android/sdk/platform-tools
```
