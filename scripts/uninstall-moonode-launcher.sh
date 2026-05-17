#!/bin/bash
#
# Moonode Launcher Uninstall Script
# Reverses what setup-moonode-launcher.sh applied:
#   - Uninstalls com.moonode.launcher
#   - Re-enables stock TV / BOX launcher packages
#   - Removes the HOME Guardian accessibility service
#   - Resets the captive-portal, sleep / screensaver, energy-saver and
#     auto-update settings the setup tweaked
#   - Re-enables Fire TV daemons (ecomode, forced OTA updater, memory hogs)
#
# Usage: ./uninstall-moonode-launcher.sh [DEVICE_IP[:PORT]] [--keep-apk]
#
# Examples:
#   ./uninstall-moonode-launcher.sh                       # USB
#   ./uninstall-moonode-launcher.sh 192.168.1.100         # Wi‑Fi, port 5555
#   ./uninstall-moonode-launcher.sh 192.168.1.100:5555    # Wi‑Fi explicit port
#   ./uninstall-moonode-launcher.sh --keep-apk            # leave the APK installed
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${YELLOW}🌙 Moonode Launcher Uninstall${NC}"
echo "===================================="
echo ""

# --- Parse args --------------------------------------------------------------
KEEP_APK=0
DEVICE_IP=""
for arg in "$@"; do
    case "$arg" in
        --keep-apk) KEEP_APK=1 ;;
        *) DEVICE_IP="$arg" ;;
    esac
done

# --- ADB sanity check --------------------------------------------------------
if ! command -v adb &> /dev/null; then
    echo -e "${RED}Error: ADB is not installed or not in PATH${NC}"
    echo "Please install Android SDK Platform Tools"
    exit 1
fi

echo -e "${BLUE}Checking ADB daemon...${NC}"
if ! adb devices &>/dev/null; then
    echo -e "${YELLOW}ADB daemon not running. Attempting to start...${NC}"
    if ! adb start-server 2>/dev/null; then
        echo -e "${RED}Failed to start ADB daemon${NC}"
        exit 1
    fi
fi

# --- Optional Wi‑Fi connect --------------------------------------------------
DEVICE_PORT="5555"
if [ -n "$DEVICE_IP" ]; then
    if [[ "$DEVICE_IP" == *:* ]]; then
        DEVICE_PORT="${DEVICE_IP##*:}"
        DEVICE_IP="${DEVICE_IP%%:*}"
    fi

    echo -e "${BLUE}Connecting to device at $DEVICE_IP:$DEVICE_PORT...${NC}"
    CONNECT_RESULT=$(adb connect "$DEVICE_IP:$DEVICE_PORT" 2>&1)
    echo "$CONNECT_RESULT"

    if echo "$CONNECT_RESULT" | grep -qE "(refused|failed|unable|cannot|error)"; then
        echo -e "${RED}Failed to connect to $DEVICE_IP:$DEVICE_PORT${NC}"
        echo "  - Ensure Wireless debugging is on"
        echo "  - Or plug USB and run without an IP"
        exit 1
    fi
    sleep 2
fi

# --- Select target device ----------------------------------------------------
if [ -n "$DEVICE_IP" ]; then
    DEVICE_SERIAL="$DEVICE_IP:$DEVICE_PORT"
    ADB_CMD="adb -s $DEVICE_SERIAL"
else
    DEVICE_COUNT=$(adb devices 2>/dev/null | grep -cE $'\tdevice$' || true)
    DEVICE_COUNT=${DEVICE_COUNT:-0}

    if [ "$DEVICE_COUNT" -eq 0 ]; then
        echo -e "${RED}No devices connected${NC}"
        adb devices 2>/dev/null || true
        exit 1
    fi

    if [ "$DEVICE_COUNT" -gt 1 ]; then
        echo -e "${RED}Multiple devices connected${NC}"
        adb devices 2>/dev/null
        echo "Run with IP address or disconnect extras: adb disconnect"
        exit 1
    fi

    ADB_CMD="adb"
fi

DEVICE_MODEL=$($ADB_CMD shell getprop ro.product.model | tr -d '\r')
echo -e "${GREEN}Device connected: $DEVICE_MODEL${NC}"
echo ""

# --- 1. Re-enable known stock launcher packages ------------------------------
echo -e "${BLUE}Re-enabling stock TV / BOX launchers...${NC}"
LAUNCHERS_TO_ENABLE=(
    "com.google.android.apps.tv.launcherx"
    "com.google.android.tvlauncher"
    "com.google.android.leanbacklauncher"
    "com.google.android.tungsten.setupwraith"
    "com.amazon.tv.launcher"
    "com.amazon.tv.leanbacklauncher"
    "com.amazon.tv.leanbacklauncher.widget"
)
for launcher in "${LAUNCHERS_TO_ENABLE[@]}"; do
    $ADB_CMD shell pm enable --user 0 "$launcher" >/dev/null 2>&1 || true
done
echo -e "${GREEN}Stock launchers re-enabled (those present on this device).${NC}"
echo ""

# --- 2. Remove HOME Guardian accessibility service ---------------------------
echo -e "${BLUE}Removing HOME Guardian accessibility service...${NC}"
HIJACK_COMPONENT="com.moonode.launcher/com.moonode.launcher.HomeHijackService"
EXISTING_SVCS=$($ADB_CMD shell settings get secure enabled_accessibility_services 2>/dev/null | tr -d '\r\n')

if [ -z "$EXISTING_SVCS" ] || [ "$EXISTING_SVCS" = "null" ]; then
    :
else
    # Strip our component out of the colon-separated list
    NEW_SVCS=$(echo "$EXISTING_SVCS" | tr ':' '\n' | grep -v -F "$HIJACK_COMPONENT" | paste -sd ':' -)
    if [ -z "$NEW_SVCS" ]; then
        $ADB_CMD shell settings delete secure enabled_accessibility_services 2>/dev/null || \
            $ADB_CMD shell settings put secure enabled_accessibility_services "" 2>/dev/null || true
        $ADB_CMD shell settings put secure accessibility_enabled 0 2>/dev/null || true
    else
        $ADB_CMD shell settings put secure enabled_accessibility_services "$NEW_SVCS" 2>/dev/null || true
    fi
fi
echo -e "${GREEN}HOME Guardian disabled.${NC}"
echo ""

# --- 3. Reset captive portal / Wi‑Fi watchdog -------------------------------
echo -e "${BLUE}Restoring captive portal detection...${NC}"
$ADB_CMD shell settings put global captive_portal_mode 1 2>/dev/null || true
$ADB_CMD shell settings put global captive_portal_detection_enabled 1 2>/dev/null || true
$ADB_CMD shell settings put global wifi_watchdog_on 1 2>/dev/null || true
echo -e "${GREEN}Captive portal detection re-enabled.${NC}"
echo ""

# --- 4. Reset kiosk power lockdown ------------------------------------------
echo -e "${BLUE}Restoring power / sleep / screensaver defaults...${NC}"
# AOSP inactivity sleep: 2 minutes is the typical OEM default
$ADB_CMD shell settings put system screen_off_timeout 120000 2>/dev/null || true

# Screensaver / DayDream
$ADB_CMD shell settings put secure screensaver_enabled 1 2>/dev/null || true
$ADB_CMD shell settings put secure screensaver_activate_on_sleep 1 2>/dev/null || true
$ADB_CMD shell settings put secure screensaver_activate_on_dock 1 2>/dev/null || true
$ADB_CMD shell settings delete secure sleep_timeout 2>/dev/null || true
$ADB_CMD shell settings delete system sleep_timeout 2>/dev/null || true
$ADB_CMD shell settings delete secure screensaver_activate_after_tv_off 2>/dev/null || true

# Stop pretending the device is always on AC
$ADB_CMD shell settings put global stay_on_while_plugged_in 0 2>/dev/null || true

# Fire OS Energy Saver / inactivity timers — let the system manage these
$ADB_CMD shell settings delete global low_power 2>/dev/null || true
$ADB_CMD shell settings delete global low_power_trigger_level 2>/dev/null || true
$ADB_CMD shell settings delete secure amazon_energy_saver_enabled 2>/dev/null || true
$ADB_CMD shell settings delete secure amazon_inactivity_sleep_enabled 2>/dev/null || true
$ADB_CMD shell settings delete secure inactivity_sleep_timeout 2>/dev/null || true

# Re-enable Fire OS Eco-mode service
$ADB_CMD shell pm enable --user 0 com.amazon.tv.ecomode >/dev/null 2>&1 || true
echo -e "${GREEN}Power / sleep / screensaver defaults restored.${NC}"
echo ""

# --- 5. Restore auto-update behaviour ---------------------------------------
echo -e "${BLUE}Restoring auto-update behaviour...${NC}"
$ADB_CMD shell settings delete global app_auto_download 2>/dev/null || true
$ADB_CMD shell settings delete global ota_disable_automatic_update 2>/dev/null || true
$ADB_CMD shell pm enable --user 0 com.amazon.tv.forcedotaupdater.v2 >/dev/null 2>&1 || true
echo -e "${GREEN}Auto-update behaviour restored to OEM defaults.${NC}"
echo ""

# --- 6. Re-enable Fire TV background daemons --------------------------------
echo -e "${BLUE}Re-enabling Fire TV background daemons (if present)...${NC}"
MEMORY_HOG_PACKAGES=(
    "com.amazon.client.metrics"
    "com.amazon.device.messaging"
    "com.amazon.tv.parentalcontrols"
    "com.amazon.diode"
)
for pkg in "${MEMORY_HOG_PACKAGES[@]}"; do
    $ADB_CMD shell pm enable --user 0 "$pkg" >/dev/null 2>&1 || true
done
echo -e "${GREEN}Fire TV daemons re-enabled (those present on this device).${NC}"
echo ""

# --- 7. Revoke WRITE_SECURE_SETTINGS from Moonode ---------------------------
echo -e "${BLUE}Revoking WRITE_SECURE_SETTINGS from Moonode Launcher...${NC}"
$ADB_CMD shell pm revoke com.moonode.launcher android.permission.WRITE_SECURE_SETTINGS >/dev/null 2>&1 || true
echo -e "${GREEN}Permission revoked.${NC}"
echo ""

# --- 8. Uninstall the APK (unless --keep-apk) -------------------------------
if [ "$KEEP_APK" -eq 0 ]; then
    echo -e "${BLUE}Uninstalling Moonode Launcher APK...${NC}"
    if $ADB_CMD shell pm list packages | grep -q "com.moonode.launcher"; then
        $ADB_CMD uninstall com.moonode.launcher >/dev/null 2>&1 || \
            $ADB_CMD shell pm uninstall --user 0 com.moonode.launcher >/dev/null 2>&1 || true
        echo -e "${GREEN}Moonode Launcher uninstalled.${NC}"
    else
        echo -e "${YELLOW}com.moonode.launcher is not installed — skipping.${NC}"
    fi
else
    echo -e "${YELLOW}--keep-apk: leaving com.moonode.launcher installed.${NC}"
fi
echo ""

# --- 9. Trigger HOME picker so the user can select the OEM launcher --------
$ADB_CMD shell input keyevent KEYCODE_HOME >/dev/null 2>&1 || true

echo -e "${GREEN}===================================="
echo -e "✓ Moonode Launcher rollback complete"
echo -e "====================================${NC}"
echo ""
echo "What was reversed:"
echo "  ✓ Stock launcher(s) re-enabled (Google TV / Android TV / Fire TV)"
echo "  ✓ HOME Guardian accessibility service removed"
echo "  ✓ Captive portal detection re-enabled"
echo "  ✓ Screen timeout / screensaver / energy saver defaults restored"
echo "  ✓ Auto-update + Fire OS daemons re-enabled"
[ "$KEEP_APK" -eq 0 ] && echo "  ✓ com.moonode.launcher uninstalled"
echo ""
echo "Next:"
echo "  1. Press HOME on the remote."
echo "  2. If asked which app should be the home screen, pick your OEM launcher"
echo "     and choose 'Always'."
echo ""
echo -e "${YELLOW}If HOME still opens nothing:${NC}"
echo "  Some OEMs hide their launcher under a different package. Run:"
echo "    adb shell cmd package query-activities -a android.intent.action.MAIN \\"
echo "         -c android.intent.category.HOME"
echo "  Then 'adb shell pm enable --user 0 <package>' on the one you recognise."
echo ""
