# 🌙 Moonode Launcher

**The smart TV launcher for Moonode** - Connecting organizations to their communities.

Moonode Launcher is a custom Android TV launcher that boots directly to [moonode.tv](https://moonode.tv), providing a seamless kiosk experience for digital signage.

## Features

- ✅ **Auto-start on boot** - Launches automatically when the device powers on
- ✅ **HOME launcher replacement** - Becomes the default home screen
- ✅ **Fullscreen WebView** - Displays moonode.tv in immersive mode
- ✅ **Offline support** - Works with moonode.tv's Service Worker for offline mode
- ✅ **Settings access** - Press Menu/F1 to access installed apps and settings
- ✅ **D-Pad navigation** - Optimized for TV remote control

## Installation

### Method 1: Install APK directly

1. Download the APK from releases
2. Install on your Android TV device:
   ```bash
   adb install moonode-launcher.apk
   ```

### Method 2: Build from source

1. Ensure Flutter is installed
2. Clone this repository
3. Build the APK:
   ```bash
   flutter build apk --release
   ```

## 🔧 Set as Default Launcher (ADB Required)

After installing Moonode Launcher, you need to set it as the default launcher. This requires ADB (Android Debug Bridge).

### Step 1: Enable Developer Options on your TV

1. Go to Settings → Device Preferences → About
2. Click on "Build" 7 times to enable Developer Options
3. Go back and enable "USB Debugging" in Developer Options

### Step 2: Connect via ADB

```bash
# Connect to your TV (replace with your TV's IP address)
adb connect 192.168.1.XXX:5555

# Or connect via USB cable
adb devices
```

### Step 3: Disable the default launcher

**For Chromecast with Google TV:**

```bash
# Disable default Google TV launcher
adb shell pm disable-user --user 0 com.google.android.apps.tv.launcherx

# Disable the fallback that re-enables it
adb shell pm disable-user --user 0 com.google.android.tungsten.setupwraith
```

**For generic Android TV boxes:**

```bash
# Find the default launcher package name
adb shell cmd package resolve-activity -a android.intent.action.MAIN -c android.intent.category.HOME

# Disable it (replace with actual package name)
adb shell pm disable-user --user 0 <package-name>
```

**For Xiaomi Mi Box / Mi TV Stick:**

```bash
adb shell pm disable-user --user 0 com.google.android.tvlauncher
```

### Step 4: Press HOME button

After disabling the default launcher, press the HOME button on your remote. Android will prompt you to choose a launcher - select "Moonode Launcher" and choose "Always".

## 📴 Offline Mode & "No Internet" Fix

Android devices will constantly check for internet connectivity and show annoying "WiFi has no internet" notifications. **This is the #1 issue for kiosk deployments.**

### Disable Captive Portal Detection (IMPORTANT!)

```bash
# Disable the "WiFi has no internet" check
adb shell settings put global captive_portal_mode 0

# For older Android versions (Android 7 and below):
adb shell settings put global captive_portal_detection_enabled 0

# Optional: Disable network notifications entirely
adb shell settings put global wifi_watchdog_on 0
```

### How Offline Mode Works

1. **First Load**: moonode.tv loads and its Service Worker caches everything
2. **Subsequent Loads**: Content served from cache, works without internet
3. **Power Loss**: Device boots → Moonode Launcher starts → WebView loads cached content

### Complete Kiosk Setup (Add to your setup script)

```bash
# 1. Install APK
adb install -r moonode-launcher.apk

# 2. Disable default launcher
adb shell pm disable-user --user 0 com.google.android.apps.tv.launcherx
adb shell pm disable-user --user 0 com.google.android.tungsten.setupwraith

# 3. Disable "No Internet" warnings (CRITICAL for offline!)
adb shell settings put global captive_portal_mode 0

# 4. Optional: Keep screen on
adb shell settings put system screen_off_timeout 2147483647
```

## ⚠️ Important Notes

- **Test before deploying** - Always test on a single device before rolling out to multiple units
- **Keep ADB access** - Ensure you can always access the device via ADB in case you need to re-enable the default launcher
- **Power loss recovery** - The launcher will automatically restart after power loss thanks to BootReceiver
- **First-time setup requires internet** - Device needs internet once to cache moonode.tv content

## 🔄 Re-enable Default Launcher

If you need to restore the original launcher:

**For Chromecast with Google TV:**

```bash
adb shell pm enable com.google.android.apps.tv.launcherx
adb shell pm enable com.google.android.tungsten.setupwraith
```

**For generic Android TV:**

```bash
adb shell pm enable <original-launcher-package>
```

## 🎮 TV Remote Controls

| Button    | Action                                     |
| --------- | ------------------------------------------ |
| HOME      | Returns to Moonode (moonode.tv)            |
| BACK      | Go back in WebView                         |
| MENU / F1 | Open Settings (app list, Android settings) |
| D-Pad     | Navigate the interface                     |
| OK/Select | Confirm selection                          |

## 🏗️ Project Structure

```
moonode-launcher/
├── android/
│   └── app/src/main/
│       ├── kotlin/com/moonode/launcher/
│       │   ├── MainActivity.kt      # Main Flutter activity
│       │   └── BootReceiver.kt      # Auto-start on boot
│       └── AndroidManifest.xml      # HOME launcher config
├── lib/
│   ├── main.dart                    # App entry point
│   ├── moonode_launcher.dart        # WebView for moonode.tv
│   ├── settings_screen.dart         # Settings & app list
│   └── launcher_channel.dart        # Native Android bridge
└── assets/                          # Moonode branding assets
```

## 📦 For Volume Shipments

When deploying to multiple devices:

1. **Pre-install** Moonode Launcher on the device image
2. **Pre-configure** ADB commands to disable default launcher
3. **Test thoroughly** on target hardware before shipping
4. **Document** the specific ADB commands for your device model

Consider creating a setup script:

```bash
#!/bin/bash
# moonode-setup.sh

echo "Setting up Moonode Launcher..."

# Install APK
adb install -r moonode-launcher.apk

# Disable default launcher (modify for your device)
adb shell pm disable-user --user 0 com.google.android.apps.tv.launcherx
adb shell pm disable-user --user 0 com.google.android.tungsten.setupwraith

echo "Setup complete! Press HOME on your remote to select Moonode."
```

## 📄 License

Based on [FLauncher](https://github.com/svrooij/flauncher) by Étienne Fesser (GPL-3.0).

Modified and maintained by Moonode © 2025.

---

**Moonode** - From Your Screen to Their Pocket 🌙
