#!/bin/bash
#
# Moonode Launcher Setup Script
# This script installs and configures Moonode Launcher as the default HOME screen
#
# Usage: ./setup-moonode-launcher.sh [DEVICE_IP[:PORT]]
#
# Examples:
#   ./setup-moonode-launcher.sh                    # Use USB connection
#   ./setup-moonode-launcher.sh 192.168.1.100     # Connect via WiFi (default port 5555)
#   ./setup-moonode-launcher.sh 192.168.1.100:5555 # Connect via WiFi (explicit port)
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Moonode branding
echo ""
echo -e "${YELLOW}🌙 Moonode Launcher Setup${NC}"
echo "=================================="
echo ""

# Check if ADB is installed
if ! command -v adb &> /dev/null; then
    echo -e "${RED}Error: ADB is not installed or not in PATH${NC}"
    echo "Please install Android SDK Platform Tools"
    exit 1
fi

# Check ADB daemon status
echo -e "${BLUE}Checking ADB daemon...${NC}"
if ! adb devices &>/dev/null; then
    echo -e "${YELLOW}ADB daemon not running. Attempting to start...${NC}"
    if ! adb start-server 2>/dev/null; then
        echo -e "${RED}Failed to start ADB daemon${NC}"
        echo ""
        echo "This is usually a macOS permissions issue. Try:"
        echo "  1. System Settings → Privacy & Security → Developer Tools"
        echo "  2. Enable ADB/Android SDK tools"
        echo "  3. Or run once with sudo: sudo adb start-server"
        echo ""
        exit 1
    fi
fi

# Parse IP and optional port
DEVICE_IP="$1"
DEVICE_PORT="5555"
if [ -n "$DEVICE_IP" ]; then
    # Check if port is included in IP (format: IP:PORT)
    if [[ "$DEVICE_IP" == *:* ]]; then
        DEVICE_PORT="${DEVICE_IP##*:}"
        DEVICE_IP="${DEVICE_IP%%:*}"
    fi
    
    echo -e "${BLUE}Connecting to device at $DEVICE_IP:$DEVICE_PORT...${NC}"
    
    # Try to connect - adb connect returns 0 even on failure, so check output
    CONNECT_RESULT=$(adb connect "$DEVICE_IP:$DEVICE_PORT" 2>&1)
    echo "$CONNECT_RESULT"
    
    if echo "$CONNECT_RESULT" | grep -qE "(refused|failed|unable|cannot|error)"; then
        echo ""
        echo -e "${RED}Failed to connect to $DEVICE_IP:$DEVICE_PORT${NC}"
        echo ""
        echo -e "${YELLOW}Troubleshooting steps:${NC}"
        echo "  1. Make sure the device is on the same WiFi network"
        echo "  2. Enable Developer Options on the device:"
        echo "     - Settings → About → Tap 'Build number' 7 times"
        echo "  3. Enable USB debugging:"
        echo "     - Settings → Developer Options → USB debugging"
        echo "  4. Enable Wireless debugging (Android 11+):"
        echo "     - Settings → Developer Options → Wireless debugging → Enable"
        echo "     - Note the IP address and port shown"
        echo "  5. For older Android versions, connect via USB first and run:"
        echo "     - adb tcpip $DEVICE_PORT"
        echo "     - Then disconnect USB and use WiFi"
        echo ""
        echo -e "${YELLOW}Alternative: Connect via USB first${NC}"
        echo "  Connect device via USB, then run:"
        echo "    adb tcpip $DEVICE_PORT"
        echo "  Then disconnect USB and run this script again with the IP"
        echo ""
        exit 1
    fi
    
    # Wait a moment for connection to establish
    sleep 2
fi

# Determine device serial for ADB commands
# If we connected via IP, use that as the serial to avoid "more than one device" errors
if [ -n "$DEVICE_IP" ]; then
    DEVICE_SERIAL="$DEVICE_IP:$DEVICE_PORT"
    ADB_CMD="adb -s $DEVICE_SERIAL"
else
    # No IP specified, check if only one device is connected
    DEVICE_COUNT=$(adb devices 2>/dev/null | grep -cE $'\tdevice$' || true)
    DEVICE_COUNT=${DEVICE_COUNT:-0}
    
    if [ "$DEVICE_COUNT" -gt 1 ]; then
        echo -e "${RED}Multiple devices connected${NC}"
        echo ""
        echo "Please specify which device to use:"
        adb devices 2>/dev/null
        echo ""
        echo "Run with IP address: ./setup-moonode-launcher.sh IP_ADDRESS"
        echo "Or disconnect extra devices: adb disconnect"
        exit 1
    fi
    
    ADB_CMD="adb"
fi

# Check device connection
echo -e "${BLUE}Checking device connection...${NC}"
DEVICE_COUNT=$($ADB_CMD devices 2>/dev/null | grep -cE $'\tdevice$' || true)
DEVICE_COUNT=${DEVICE_COUNT:-0}
if [ "$DEVICE_COUNT" -eq 0 ]; then
    echo -e "${RED}No devices connected${NC}"
    echo ""
    echo "Available options:"
    echo "  1. Connect device via USB and run: ./setup-moonode-launcher.sh"
    echo "  2. Connect via WiFi: ./setup-moonode-launcher.sh IP_ADDRESS[:PORT]"
    echo ""
    echo "Current ADB devices:"
    adb devices 2>/dev/null || echo "  (ADB not responding)"
    echo ""
    exit 1
fi

echo -e "${GREEN}Device connected!${NC}"
echo ""

# Get device info
DEVICE_MODEL=$($ADB_CMD shell getprop ro.product.model | tr -d '\r')
ANDROID_VERSION=$($ADB_CMD shell getprop ro.build.version.release | tr -d '\r')
echo "Device: $DEVICE_MODEL"
echo "Android: $ANDROID_VERSION"
echo ""

# Check if APK exists
APK_PATH="./moonode-launcher.apk"
if [ ! -f "$APK_PATH" ]; then
    APK_PATH="../build/app/outputs/flutter-apk/app-release.apk"
fi
if [ ! -f "$APK_PATH" ]; then
    echo -e "${YELLOW}APK not found. Building...${NC}"
    cd "$(dirname "$0")/.."
    flutter build apk --release
    APK_PATH="./build/app/outputs/flutter-apk/app-release.apk"
fi

# Install Moonode Launcher
echo -e "${BLUE}Installing Moonode Launcher...${NC}"
$ADB_CMD install -r "$APK_PATH" || {
    echo -e "${RED}Failed to install APK${NC}"
    exit 1
}
echo -e "${GREEN}Moonode Launcher installed!${NC}"
echo ""

# Grant WRITE_SECURE_SETTINGS so the launcher can self-heal the HOME Guardian
# accessibility service after Fire OS auto-disables it (which happens on every
# APK reinstall and after some OS updates). Without this, the user would need
# to manually re-toggle the service in Accessibility settings each time.
# This grant requires ADB and persists for the life of the install.
echo -e "${BLUE}Granting self-heal permission (WRITE_SECURE_SETTINGS)...${NC}"
$ADB_CMD shell pm grant com.moonode.launcher android.permission.WRITE_SECURE_SETTINGS 2>/dev/null && \
    echo -e "${GREEN}Self-heal permission granted!${NC}" || \
    echo -e "${YELLOW}Could not grant WRITE_SECURE_SETTINGS - HOME Guardian will need manual re-enable if Fire OS disables it${NC}"
echo ""

# Detect current default launcher
echo -e "${BLUE}Detecting current launcher...${NC}"
CURRENT_LAUNCHER=$($ADB_CMD shell cmd package resolve-activity -a android.intent.action.MAIN -c android.intent.category.HOME | grep packageName | head -1 | cut -d'=' -f2 | tr -d '\r')
echo "Current launcher: $CURRENT_LAUNCHER"
echo ""

# Known launcher packages to disable
LAUNCHERS_TO_DISABLE=(
    "com.google.android.apps.tv.launcherx"        # Google TV
    "com.google.android.tvlauncher"               # Android TV
    "com.google.android.leanbacklauncher"         # Older Android TV
    "com.google.android.tungsten.setupwraith"     # Google TV fallback
    "com.amazon.tv.launcher"                       # Fire TV
)

# Disable known launchers
echo -e "${BLUE}Disabling default launchers...${NC}"
for launcher in "${LAUNCHERS_TO_DISABLE[@]}"; do
    if $ADB_CMD shell pm list packages | grep -q "$launcher"; then
        echo "  Disabling $launcher..."
        $ADB_CMD shell pm disable-user --user 0 "$launcher" 2>/dev/null || true
    fi
done

# Also disable the detected current launcher if different
if [ -n "$CURRENT_LAUNCHER" ] && [ "$CURRENT_LAUNCHER" != "com.moonode.launcher" ]; then
    echo "  Disabling $CURRENT_LAUNCHER..."
    $ADB_CMD shell pm disable-user --user 0 "$CURRENT_LAUNCHER" 2>/dev/null || true
fi

echo -e "${GREEN}Default launchers disabled!${NC}"
echo ""

# Disable captive portal detection (prevents "No Internet" warnings)
echo -e "${BLUE}Configuring offline mode...${NC}"
echo "  Disabling 'WiFi has no internet' warnings..."
$ADB_CMD shell settings put global captive_portal_mode 0 2>/dev/null || true
$ADB_CMD shell settings put global captive_portal_detection_enabled 0 2>/dev/null || true
$ADB_CMD shell settings put global wifi_watchdog_on 0 2>/dev/null || true
echo -e "${GREEN}Offline mode configured!${NC}"
echo ""

# =============================================================================
# Kiosk power lockdown: keep the display lit 24/7 for digital signage.
#
# Fire TV has THREE independent power-management layers and you must disable
# all three. AOSP screen_off_timeout alone is NOT enough on Fire OS.
#
#   1) AOSP inactivity sleep      (system.screen_off_timeout)
#   2) Fire OS DayDream/screensaver photo carousel
#      (secure.screensaver_*, secure.sleep_timeout)
#   3) Amazon "Energy Saver" 4h auto-shutoff
#      (com.amazon.tv.devicecontrolsettings + EcoMode service)
#
# Layers 1+2 are 100% automatable via ADB. Layer 3 (the 4-hour off) is a
# closed Amazon service. We do best-effort here: stay_on_while_plugged_in=7
# tells the framework the device is "always charging" which on most Fire OS
# builds bypasses the Eco-mode timer entirely. If it doesn't take on a
# particular Fire OS version, the manual UI toggle is:
#   Settings -> Preferences -> Power -> Energy Saver -> Off
# (also called "Sleep Timer" on some builds).
# =============================================================================
echo -e "${BLUE}Configuring kiosk power lockdown...${NC}"

# --- Layer 1: AOSP inactivity sleep ------------------------------------------
# Set to maximum (~24.8 days). 2147483647 = Int32 max ms.
$ADB_CMD shell settings put system screen_off_timeout 2147483647 2>/dev/null || true

# --- Layer 2: Fire OS screensaver / DayDream ---------------------------------
# These are the keys that control the "Your photos in a slideshow" carousel
# that appears after a few minutes of inactivity on Fire TV.
$ADB_CMD shell settings put secure screensaver_enabled 0 2>/dev/null || true
$ADB_CMD shell settings put secure screensaver_activate_on_sleep 0 2>/dev/null || true
$ADB_CMD shell settings put secure screensaver_activate_on_dock 0 2>/dev/null || true
# sleep_timeout = how long until Fire OS goes from active to screensaver.
# -1 / 0 = never on most builds; we set both to be safe across Fire OS 5/6/7.
$ADB_CMD shell settings put secure sleep_timeout 0 2>/dev/null || true
$ADB_CMD shell settings put system sleep_timeout 0 2>/dev/null || true
# Some Fire OS builds expose a separate "ambient" / "after_TV_off" screensaver.
$ADB_CMD shell settings put secure screensaver_activate_after_tv_off 0 2>/dev/null || true

# --- Layer 3: Amazon "Energy Saver" / 4h auto-off ----------------------------
# Tell the framework the device is always plugged into AC | USB | Wireless
# (mask 7). On most Fire OS versions this short-circuits the Eco-mode timer
# because the OS thinks it's a permanently-powered appliance, not a remote-
# controlled set-top box that the user "walked away from".
$ADB_CMD shell settings put global stay_on_while_plugged_in 7 2>/dev/null || true
# Fire OS 6+ stores the Energy Saver toggle under several different keys
# depending on build. We try all of them - the ones that don't exist no-op.
$ADB_CMD shell settings put global low_power 0 2>/dev/null || true
$ADB_CMD shell settings put global low_power_trigger_level 0 2>/dev/null || true
# Amazon-internal toggles seen on Fire OS 7 (AFTKAUK / AFTKA Plus / AFTKMST12):
$ADB_CMD shell settings put secure amazon_energy_saver_enabled 0 2>/dev/null || true
$ADB_CMD shell settings put secure amazon_inactivity_sleep_enabled 0 2>/dev/null || true
$ADB_CMD shell settings put secure inactivity_sleep_timeout 0 2>/dev/null || true
# As a last-resort hammer on Fire OS builds that expose it, kill the watchdog
# job entirely. Safe no-op if the package doesn't exist on this build.
$ADB_CMD shell pm disable-user --user 0 com.amazon.tv.ecomode 2>/dev/null || true

# --- Verify layer 1 took ----------------------------------------------------
CURRENT_TIMEOUT=$($ADB_CMD shell settings get system screen_off_timeout 2>/dev/null | tr -d '\r\n')
if [ "$CURRENT_TIMEOUT" = "2147483647" ]; then
    echo -e "${GREEN}Kiosk power lockdown applied!${NC}"
else
    echo -e "${YELLOW}Warning: screen_off_timeout = $CURRENT_TIMEOUT (expected 2147483647)${NC}"
    echo -e "${YELLOW}You may need to also disable Energy Saver manually:${NC}"
    echo -e "${YELLOW}  Settings -> Preferences -> Power -> Energy Saver -> Off${NC}"
fi
echo ""

# Fire TV / Fire OS specific: lock down auto-updates so the OS does not silently
# re-enable Amazon launcher packages, push OS updates that change behaviour, or
# pull APK updates from the Appstore overnight. Safe to run on Android TV too -
# the package commands fail silently when the package does not exist.
# Enable the HOME Guardian accessibility service immediately. The launcher
# will also self-heal it on subsequent starts via WRITE_SECURE_SETTINGS, but
# enabling it here guarantees HOME button protection is live from the very
# first boot - no need to wait for the user to open Moonode.
echo -e "${BLUE}Enabling HOME Guardian accessibility service...${NC}"
HIJACK_COMPONENT="com.moonode.launcher/com.moonode.launcher.HomeHijackService"
EXISTING_SVCS=$($ADB_CMD shell settings get secure enabled_accessibility_services 2>/dev/null | tr -d '\r\n')
if [ -z "$EXISTING_SVCS" ] || [ "$EXISTING_SVCS" = "null" ]; then
    NEW_SVCS="$HIJACK_COMPONENT"
elif echo "$EXISTING_SVCS" | grep -q "$HIJACK_COMPONENT"; then
    NEW_SVCS="$EXISTING_SVCS"
else
    NEW_SVCS="$EXISTING_SVCS:$HIJACK_COMPONENT"
fi
$ADB_CMD shell settings put secure enabled_accessibility_services "$NEW_SVCS" 2>/dev/null || true
$ADB_CMD shell settings put secure accessibility_enabled 1 2>/dev/null || true
echo -e "${GREEN}HOME Guardian enabled!${NC}"
echo ""

# Best-effort: reduce memory pressure on low-RAM Fire TV Sticks (~921 MB
# total) by disabling non-essential Amazon background daemons. Most of these
# are protected packages on current Fire OS builds and the disable will
# silently fail - that's fine, the launcher's own onTrimMemory + cold-start
# auto-recovery handles the rest. Older Fire OS builds may allow these to
# be disabled, in which case this frees ~50-80 MB.
MEMORY_HOG_PACKAGES=(
    "com.amazon.client.metrics"          # Minerva analytics
    "com.amazon.device.messaging"        # Cloud push notifications
    "com.amazon.tv.parentalcontrols"     # Parental controls UI
    "com.amazon.diode"                   # External event collector
)
for pkg in "${MEMORY_HOG_PACKAGES[@]}"; do
    $ADB_CMD shell pm disable-user --user 0 "$pkg" >/dev/null 2>&1 || true
done


echo -e "${BLUE}Locking down auto-updates (Fire TV protections)...${NC}"
# 1) Tell the Appstore not to auto-download app updates in the background.
$ADB_CMD shell settings put global app_auto_download 0 2>/dev/null || true
# 2) Honour the AOSP-style flag some Fire OS builds respect for OTAs.
$ADB_CMD shell settings put global ota_disable_automatic_update 1 2>/dev/null || true
# 3) Disable Amazon's "forced OTA updater" package - this is the daemon that
#    aggressively pushes Fire OS system updates. It is NOT a protected package
#    so disable-user works. The core OTA service (com.amazon.device.software.ota)
#    cannot be disabled without root, but without the forced updater Fire OS
#    will not push updates aggressively in the background.
if $ADB_CMD shell pm list packages | grep -q "com.amazon.tv.forcedotaupdater.v2"; then
    echo "  Disabling Amazon forced OTA updater..."
    $ADB_CMD shell pm disable-user --user 0 com.amazon.tv.forcedotaupdater.v2 2>/dev/null || true
fi
echo -e "${GREEN}Auto-update protections applied!${NC}"
echo ""

# Reset overscan + display density to defaults so Moonode covers the full
# screen. NOTE: `wm overscan` was removed in Android 11 / Fire OS 8, so on
# newer sticks these calls print "Unknown command: overscan" and no-op.
# That's harmless - Fire OS 6+ always uses 100% of the screen anyway. We
# silence the chatter on stderr so the install output stays clean.
echo -e "${BLUE}Configuring display settings...${NC}"
$ADB_CMD shell wm overscan 0,0,0,0 >/dev/null 2>&1 || true
$ADB_CMD shell wm overscan reset >/dev/null 2>&1 || true
$ADB_CMD shell wm density reset >/dev/null 2>&1 || true
echo -e "${GREEN}Display settings configured!${NC}"
echo ""

# Verify Moonode is installed
echo -e "${BLUE}Verifying installation...${NC}"
if $ADB_CMD shell pm list packages | grep -q "com.moonode.launcher"; then
    echo -e "${GREEN}✓ Moonode Launcher is installed${NC}"
else
    echo -e "${RED}✗ Moonode Launcher not found${NC}"
    exit 1
fi

# Final instructions
echo ""
echo -e "${GREEN}=================================="
echo -e "🎉 Setup Complete!"
echo -e "==================================${NC}"
echo ""
echo "What's configured:"
echo "  ✓ Moonode Launcher installed"
echo "  ✓ Default launcher disabled"
echo "  ✓ 'No Internet' warnings disabled"
echo "  ✓ Screen always-on (AOSP sleep + Fire OS screensaver + Energy Saver)"
echo "  ✓ Display overscan reset (full screen)"
echo "  ✓ Fire TV auto-updates suppressed (apps + forced OTAs)"
echo "  ✓ HOME Guardian enabled + self-healing (via WRITE_SECURE_SETTINGS grant)"
echo ""
echo -e "${YELLOW}If the screen still goes black after ~4 hours of inactivity:${NC}"
echo "    Settings → Preferences → Power → Energy Saver → Off"
echo "  (Some Fire OS builds gate this behind the on-screen UI only.)"
echo ""
echo "Next steps:"
echo "  1. Press the HOME button on your TV remote"
echo "  2. If prompted, select 'Moonode Launcher'"
echo "  3. Choose 'Always' to make it permanent"
echo "  4. Connect to WiFi and let moonode.tv load (caches for offline)"
echo ""
echo -e "${YELLOW}IMPORTANT: First load requires internet to cache content!${NC}"
echo ""
echo -e "${YELLOW}To restore original launcher:${NC}"
echo "  adb shell pm enable com.google.android.apps.tv.launcherx"
echo "  adb shell pm enable com.google.android.tungsten.setupwraith"
echo "  adb shell settings put global captive_portal_mode 1"
echo ""
echo -e "${BLUE}🌙 Moonode - From Your Screen to Their Pocket${NC}"
echo ""

