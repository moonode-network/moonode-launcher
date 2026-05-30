#!/bin/bash
#
# Moonode Launcher Setup Script
# This script installs and configures Moonode Launcher as the default HOME screen
#
# Usage: ./setup-moonode-launcher.sh [--soft] [--lockdown] [DEVICE_IP[:PORT]]
#
# Flags:
#   --soft          NEVER disable the stock launcher. Use the system HOME
#                   picker so Moonode is selected as default but the original
#                   launcher remains available as a fallback. Auto-enabled on
#                   Xiaomi MiTV / MIUI builds.
#   --lockdown      After Moonode is verified running, disable the stock
#                   Google TV launcher packages so Moonode wins HOME. On
#                   Xiaomi, MIUI re-enables them on reboot - pair this with
#                   a BootReceiver build that retries launching Moonode on boot.
#
# Examples:
#   ./setup-moonode-launcher.sh                          # USB connection
#   ./setup-moonode-launcher.sh 192.168.1.100            # Connect via WiFi
#   ./setup-moonode-launcher.sh 192.168.1.100:5555       # Explicit port
#   ./setup-moonode-launcher.sh --soft 192.168.1.100     # Safe mode (Xiaomi)
#   ./setup-moonode-launcher.sh --lockdown 172.20.10.2   # Xiaomi: make Moonode HOME
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

# Parse flags + IP + optional port. Flags can appear before or after the IP.
SOFT_MODE=0
LOCKDOWN_MODE=0
DEVICE_IP=""
DEVICE_PORT="5555"
SOFT_MODE_REASON=""

for arg in "$@"; do
    case "$arg" in
        --soft)
            SOFT_MODE=1
            SOFT_MODE_REASON="--soft flag passed"
            ;;
        --lockdown)
            LOCKDOWN_MODE=1
            ;;
        --help|-h)
            sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            if [ -z "$DEVICE_IP" ]; then
                DEVICE_IP="$arg"
            fi
            ;;
    esac
done

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

# =============================================================================
# Device-type detection.
#
# Fire TV and Android TV / Google TV behave very differently and the rest of
# the script branches off this:
#
#   Fire TV (Amazon)
#     - Amazon protects its stock launcher; the standard Android HOME picker
#       does not work. We have to pm disable-user the Amazon launcher and
#       enable the HOME Guardian accessibility service.
#     - Fire OS has Amazon-specific energy-saver / forced-OTA daemons that
#       need extra lockdown.
#
#   Android TV / Google TV (TCL, Sony, Hisense, Xiaomi, plain GTV, etc.)
#     - The OS has a working HOME activity API (cmd package set-home-activity)
#       so we try the clean path first.
#     - Google Backdrop ambient-dream activity overlays everything ~5s after
#       boot. If we don't kill it the operator sees a black screen and
#       assumes the install bricked the TV.
#     - Fire OS daemons / HOME Guardian don't exist on these builds, so we
#       skip them.
#
# Detection is "is this Amazon?" because Amazon is the lone exception. Every
# other OEM (and plain AOSP TV) gets the ATV path.
# =============================================================================
echo -e "${BLUE}Detecting device type...${NC}"
MANUFACTURER=$($ADB_CMD shell getprop ro.product.manufacturer 2>/dev/null | tr -d '\r')
BRAND=$($ADB_CMD shell getprop ro.product.brand 2>/dev/null | tr -d '\r')
MFR_LC=$(echo "$MANUFACTURER" | tr '[:upper:]' '[:lower:]')
BRAND_LC=$(echo "$BRAND" | tr '[:upper:]' '[:lower:]')
HAS_AMAZON_LAUNCHER=$($ADB_CMD shell pm list packages 2>/dev/null | grep -c '^package:com\.amazon\.tv\.launcher$' || true)
HAS_AMAZON_LAUNCHER=${HAS_AMAZON_LAUNCHER:-0}

IS_FIRETV=0
IS_ATV=0
IS_XIAOMI=0
if [ "$MFR_LC" = "amazon" ] || [ "$BRAND_LC" = "amazon" ] || [ "$HAS_AMAZON_LAUNCHER" -gt 0 ]; then
    IS_FIRETV=1
    DEVICE_KIND="Fire TV"
else
    IS_ATV=1
    DEVICE_KIND="Android TV / Google TV"
fi
if [ "$MFR_LC" = "xiaomi" ] || [ "$BRAND_LC" = "xiaomi" ] || echo "$DEVICE_MODEL" | grep -qiE '(mitv|mi tv|mibox|mi box)'; then
    IS_XIAOMI=1
    DEVICE_KIND="$DEVICE_KIND (Xiaomi)"
fi
echo -e "${GREEN}Detected: $DEVICE_KIND${NC}"

# Xiaomi MiTV / MIUI does not honour `cmd package set-home-activity` and
# silently fails to promote a third-party HOME activity. The fallback path
# (pm disable-user on the stock launcher) leaves the device with no HOME
# resolver after a reboot, producing a black screen with no remote
# affordance. Force --soft on Xiaomi unconditionally; the user can still
# pick Moonode through the system HOME picker.
if [ "$IS_XIAOMI" -eq 1 ] && [ "$SOFT_MODE" -ne 1 ]; then
    SOFT_MODE=1
    SOFT_MODE_REASON="Xiaomi auto-detected"
    echo -e "${YELLOW}Xiaomi device → forcing --soft mode (stock launcher will be left enabled).${NC}"
fi

if [ "$SOFT_MODE" -eq 1 ]; then
    echo -e "${YELLOW}Soft mode active ($SOFT_MODE_REASON): stock launcher will NOT be disabled.${NC}"
fi
echo ""

# ---------------------------------------------------------------------------
# HOME detection helpers.
#
# On most Android TV builds, `cmd package resolve-activity` is the source of
# truth. Xiaomi MiTV (Android 14) is different: the operator's HOME picker
# selection is stored in the RoleManager (`android.app.role.HOME` →
# holders=com.moonode.launcher) but resolve-activity keeps returning the
# priv-app Google launcher. We must check BOTH or the soft-mode poll loop
# never exits even after a correct remote selection.
# ---------------------------------------------------------------------------
get_resolved_home() {
    $ADB_CMD shell cmd package resolve-activity \
        -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null \
        | grep packageName | head -1 | cut -d'=' -f2 | tr -d '\r'
}

get_home_role_holder() {
    $ADB_CMD shell dumpsys role 2>/dev/null \
        | grep -A2 'android.app.role.HOME' \
        | grep 'holders=' | head -1 \
        | sed 's/.*holders=//' | tr -d '\r'
}

moonode_is_default_home() {
    local resolved role_holder
    resolved=$(get_resolved_home)
    if [ "$resolved" = "com.moonode.launcher" ]; then
        NEW_HOME="com.moonode.launcher"
        return 0
    fi
    role_holder=$(get_home_role_holder)
    if [ "$role_holder" = "com.moonode.launcher" ]; then
        NEW_HOME="com.moonode.launcher"
        return 0
    fi
    NEW_HOME="$resolved"
    return 1
}

# =============================================================================
# Captive-portal probe off - BEFORE install.
#
# On Google-certified Android TV / Google TV the first network request the
# WebView makes when Moonode launches (loading moonode.tv) is intercepted by
# Android's captive-portal probe. That intercept blocks the Service Worker
# registration on first run, so the launcher's Cache Storage stays empty.
# On the NEXT reboot the device boots offline (or the SW reads stale state)
# and shows "offline content unavailable".
#
# Doing this BEFORE the launcher's first network touch removes that race.
# On Fire TV the same commands are a no-op cost (Fire OS doesn't run the
# same probe anyway), so it's safe to do unconditionally and early.
# =============================================================================
echo -e "${BLUE}Disabling captive-portal probe (so the Service Worker can cache)...${NC}"
$ADB_CMD shell settings put global captive_portal_mode 0 2>/dev/null || true
$ADB_CMD shell settings put global captive_portal_detection_enabled 0 2>/dev/null || true
$ADB_CMD shell settings put global wifi_watchdog_on 0 2>/dev/null || true
echo -e "${GREEN}Captive-portal probe disabled.${NC}"
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

# Detect current default launcher (informational on ATV, action target on Fire TV)
echo -e "${BLUE}Detecting current launcher...${NC}"
CURRENT_LAUNCHER=$($ADB_CMD shell cmd package resolve-activity -a android.intent.action.MAIN -c android.intent.category.HOME | grep packageName | head -1 | cut -d'=' -f2 | tr -d '\r')
echo "Current launcher: $CURRENT_LAUNCHER"
echo ""

if [ "$IS_FIRETV" -eq 1 ]; then
    # -------------------------------------------------------------------------
    # Fire TV path: brute-force HOME by disabling every known Amazon launcher.
    # This is the only reliable way on Fire OS because Amazon bypasses the
    # standard Android HOME picker.
    # -------------------------------------------------------------------------
    LAUNCHERS_TO_DISABLE=(
        "com.amazon.tv.launcher"
        "com.amazon.firehomestarter"
        "com.amazon.firelauncher"
        "com.amazon.tv.leanbacklauncher"
        "com.amazon.tv.leanbacklauncher.widget"
    )

    echo -e "${BLUE}Disabling Amazon launchers...${NC}"
    for launcher in "${LAUNCHERS_TO_DISABLE[@]}"; do
        if $ADB_CMD shell pm list packages | grep -q "$launcher"; then
            echo "  Disabling $launcher..."
            $ADB_CMD shell pm disable-user --user 0 "$launcher" 2>/dev/null || true
        fi
    done

    # Also disable whatever the current resolver is pointing at, in case the
    # device ships a launcher we didn't list above.
    if [ -n "$CURRENT_LAUNCHER" ] && [ "$CURRENT_LAUNCHER" != "com.moonode.launcher" ]; then
        echo "  Disabling current launcher $CURRENT_LAUNCHER..."
        $ADB_CMD shell pm disable-user --user 0 "$CURRENT_LAUNCHER" 2>/dev/null || true
    fi

    echo -e "${GREEN}Amazon launchers disabled!${NC}"
    echo ""
else
    # -------------------------------------------------------------------------
    # Android TV / Google TV path: try the clean OS API first, fall back to
    # disabling the stock launcher only if needed.
    #
    # Step 1: Kill Google Backdrop. The ambient/dream activity overlays the
    #         entire screen ~5s after boot on TCL / Google TV builds and looks
    #         identical to a black-screen brick to operators.
    # Step 2: Clear preferred-activity associations so the HOME resolver will
    #         actually re-evaluate.
    # Step 3: Try cmd package set-home-activity. This is the supported API
    #         path and works silently on many builds. On Google-certified TVs
    #         it sometimes does nothing - that's why we verify afterwards.
    # Step 4: If verify still resolves to the stock launcher, disable it with
    #         pm disable-user --user 0. This is what actually worked on the
    #         TCL AT11 we hardened.
    # -------------------------------------------------------------------------
    echo -e "${BLUE}Disabling Google Backdrop ambient dream (prevents black-screen-after-boot)...${NC}"
    $ADB_CMD shell am force-stop com.google.android.backdrop 2>/dev/null || true
    $ADB_CMD shell pm disable-user --user 0 com.google.android.backdrop 2>/dev/null || true
    echo -e "${GREEN}Backdrop dream disabled.${NC}"
    echo ""

    echo -e "${BLUE}Setting Moonode as HOME (clean path)...${NC}"
    $ADB_CMD shell pm clear-preferred-activities com.google.android.tvlauncher 2>/dev/null || true
    $ADB_CMD shell pm clear-preferred-activities com.google.android.apps.tv.launcherx 2>/dev/null || true
    $ADB_CMD shell pm clear-preferred-activities com.moonode.launcher 2>/dev/null || true
    $ADB_CMD shell cmd package set-home-activity com.moonode.launcher/com.moonode.launcher.MainActivity 2>/dev/null || true

    NEW_HOME=$($ADB_CMD shell cmd package resolve-activity -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null | grep packageName | head -1 | cut -d'=' -f2 | tr -d '\r')
    if [ "$NEW_HOME" = "com.moonode.launcher" ]; then
        echo -e "${GREEN}HOME = com.moonode.launcher (clean API path worked).${NC}"
    elif [ "$SOFT_MODE" -eq 1 ]; then
        # Soft mode: the stock launcher stays enabled. We open the system
        # HOME picker on the TV so the operator selects Moonode manually.
        # If they ever need to recover (Moonode crashes, content fails), a
        # single press of HOME re-shows the picker and they can swap back.
        echo -e "${YELLOW}HOME still = $NEW_HOME after set-home-activity.${NC}"
        echo -e "${BLUE}Soft mode: opening the system HOME picker on the TV...${NC}"
        $ADB_CMD shell am start -a android.settings.HOME_SETTINGS >/dev/null 2>&1 || true
        sleep 1
        echo ""
        echo -e "${YELLOW}>>> ON THE TV: pick 'Moonode Launcher' as the default home app. <<<${NC}"
        echo "    (Use the remote arrows + OK button.)"
        echo ""
        # Wait for the operator's pick. Two modes:
        #   - TTY (operator at a terminal): also accept ENTER as an early
        #     "I'm done" signal so they don't have to wait for the poll.
        #   - non-TTY (script piped / run by another tool): just poll the
        #     resolver, no input expected.
        # In both cases we time-box the wait at 90s and report what we see.
        echo "    Polling for Moonode HOME selection (up to 90s)..."
        echo "    (On Xiaomi, press ENTER here once you've picked Moonode on the TV.)"
        WAITED=0
        MOONODE_HOME_OK=0
        while [ "$WAITED" -lt 90 ]; do
            if moonode_is_default_home; then
                MOONODE_HOME_OK=1
                break
            fi
            if [ -t 0 ] && read -r -t 1 _ 2>/dev/null; then
                if moonode_is_default_home; then
                    MOONODE_HOME_OK=1
                fi
                break
            else
                sleep 1
            fi
            WAITED=$((WAITED + 1))
        done
        if [ "$MOONODE_HOME_OK" -eq 1 ]; then
            if [ "$IS_XIAOMI" -eq 1 ] && [ "$(get_resolved_home)" != "com.moonode.launcher" ]; then
                echo -e "${GREEN}HOME role = com.moonode.launcher (Xiaomi picker accepted).${NC}"
                echo -e "${YELLOW}Note: Xiaomi may still show Google TV on HOME press; Moonode launches on boot.${NC}"
                $ADB_CMD shell am start -n com.moonode.launcher/com.moonode.launcher.MainActivity >/dev/null 2>&1 || true
            else
                echo -e "${GREEN}HOME = com.moonode.launcher (HOME picker selection accepted).${NC}"
            fi
        else
            echo -e "${YELLOW}HOME still = $NEW_HOME. Moonode is INSTALLED but not yet the default.${NC}"
            echo -e "${YELLOW}You can finish later from the TV UI:${NC}"
            echo "    Settings → Apps → Default apps → Home app → Moonode Launcher"
            echo -e "${YELLOW}Stock launcher remains enabled - device is safe to reboot.${NC}"
        fi
    else
        echo -e "${YELLOW}HOME still = $NEW_HOME after set-home-activity.${NC}"
        echo -e "${YELLOW}Falling back to pm disable-user on the stock launcher...${NC}"
        for launcher in \
            "com.google.android.tvlauncher" \
            "com.google.android.apps.tv.launcherx" \
            "com.google.android.leanbacklauncher" \
            "com.google.android.tungsten.setupwraith"; do
            if $ADB_CMD shell pm list packages | grep -q "$launcher"; then
                echo "  Disabling $launcher..."
                $ADB_CMD shell pm disable-user --user 0 "$launcher" 2>/dev/null || true
            fi
        done
        NEW_HOME=$($ADB_CMD shell cmd package resolve-activity -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null | grep packageName | head -1 | cut -d'=' -f2 | tr -d '\r')
        if [ "$NEW_HOME" = "com.moonode.launcher" ]; then
            echo -e "${GREEN}HOME = com.moonode.launcher (fallback path worked).${NC}"
        else
            echo -e "${RED}HOME still = $NEW_HOME after fallback. Manual step required:${NC}"
            echo "    adb shell am start -a android.settings.HOME_SETTINGS"
            echo "  Then pick Moonode Launcher with the remote."
        fi
    fi
    echo ""
fi

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

# HOME Guardian: Fire-TV-only.
#
# This accessibility service watches for Amazon HOME packages winning a focus
# race (Amazon re-launches its launcher silently after some events) and
# re-fires Moonode. It targets Amazon package names exclusively, so on
# Android TV / Google TV it would do nothing useful but still show as an
# enabled accessibility service in Settings - which spooks operators. Skip
# it on ATV.
if [ "$IS_FIRETV" -eq 1 ]; then
    echo -e "${BLUE}Enabling HOME Guardian accessibility service (Fire TV)...${NC}"
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
fi

# Fire-TV-only: reduce memory pressure on low-RAM Fire TV Sticks (~921 MB
# total) by disabling non-essential Amazon background daemons. These packages
# do not exist on Android TV / Google TV, so we skip the loop entirely there
# to keep the install output clean.
if [ "$IS_FIRETV" -eq 1 ]; then
    MEMORY_HOG_PACKAGES=(
        "com.amazon.client.metrics"          # Minerva analytics
        "com.amazon.device.messaging"        # Cloud push notifications
        "com.amazon.tv.parentalcontrols"     # Parental controls UI
        "com.amazon.diode"                   # External event collector
    )
    for pkg in "${MEMORY_HOG_PACKAGES[@]}"; do
        $ADB_CMD shell pm disable-user --user 0 "$pkg" >/dev/null 2>&1 || true
    done
fi


# Auto-update lockdown.
# The two `settings put global` keys are generic AOSP and useful on both
# platforms. The Amazon forced-OTA disable is Fire-TV-only because the
# package does not exist on Android TV.
echo -e "${BLUE}Locking down auto-updates...${NC}"
$ADB_CMD shell settings put global app_auto_download 0 2>/dev/null || true
$ADB_CMD shell settings put global ota_disable_automatic_update 1 2>/dev/null || true
if [ "$IS_FIRETV" -eq 1 ]; then
    if $ADB_CMD shell pm list packages | grep -q "com.amazon.tv.forcedotaupdater.v2"; then
        echo "  Disabling Amazon forced OTA updater..."
        $ADB_CMD shell pm disable-user --user 0 com.amazon.tv.forcedotaupdater.v2 2>/dev/null || true
    fi
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
echo ""

# =============================================================================
# Cache warm-up window.
#
# Moonode's offline mode is driven by the WebView Service Worker, which has
# to register and populate Cache Storage with moonode.tv assets on first
# online run. If the operator runs `adb reboot` (or just unplugs the TV)
# before this finishes, the launcher boots offline next time with empty
# Cache Storage and shows "offline content unavailable".
#
# This is the failure mode we hit on the TCL AT11 manual install. The fix:
# kick Moonode on screen, then hold the script here for ~3 minutes so the
# SW finishes installing assets into Cache Storage and IndexedDB.
#
# This is intentionally a passive wait instead of an active disk poll
# because `dumpsys diskstats` output format varies across Android versions
# and OEMs, and /data/data/com.moonode.launcher isn't readable from a
# non-root adb shell. Operators wanting concrete proof can verify via
# chrome://inspect (see TROUBLESHOOTING.md).
# =============================================================================
echo -e "${BLUE}Kicking Moonode on screen to start the Service Worker...${NC}"
$ADB_CMD shell am start -n com.moonode.launcher/com.moonode.launcher.MainActivity >/dev/null 2>&1 || true
sleep 5

echo -e "${BLUE}Cache warm-up window: 3 minutes - DO NOT reboot the TV yet.${NC}"
for s in 180 160 140 120 100 80 60 40 20; do
    printf "\r  %3ds remaining (do not reboot)...  " "$s"
    sleep 20
done
printf "\n"
echo -e "${GREEN}Warm-up window complete. Offline reboot should now work.${NC}"
echo ""

# =============================================================================
# Optional lockdown (--lockdown flag).
#
# Soft mode leaves the stock launcher enabled so the operator can recover
# without ADB. Once Moonode has been verified on-screen and the cache is
# warm, --lockdown disables the Google TV launcher packages so Moonode
# actually wins the HOME intent.
#
# On Xiaomi, MIUI re-enables disabled system launchers on every reboot.
# Pair lockdown with a BootReceiver build that retries launching Moonode
# on boot (same strategy as Fire TV).
# =============================================================================
LOCKDOWN_APPLIED=0
if [ "$LOCKDOWN_MODE" -eq 1 ] && [ "$IS_FIRETV" -eq 0 ]; then
    echo -e "${BLUE}Lockdown: verifying Moonode is on screen before disabling stock launcher...${NC}"
    FOCUS=$($ADB_CMD shell dumpsys window 2>/dev/null | grep mCurrentFocus | head -1 | tr -d '\r')
    if echo "$FOCUS" | grep -q "com.moonode.launcher"; then
        echo -e "${GREEN}Moonode is foreground - safe to lock down.${NC}"
        for launcher in \
            "com.google.android.tvlauncher" \
            "com.google.android.apps.tv.launcherx" \
            "com.google.android.leanbacklauncher" \
            "com.google.android.tungsten.setupwraith"; do
            if $ADB_CMD shell pm list packages | grep -q "$launcher"; then
                echo "  Disabling $launcher..."
                $ADB_CMD shell pm disable-user --user 0 "$launcher" 2>/dev/null || true
            fi
        done
        $ADB_CMD shell input keyevent KEYCODE_HOME >/dev/null 2>&1 || true
        sleep 2
        if moonode_is_default_home; then
            LOCKDOWN_APPLIED=1
            echo -e "${GREEN}Lockdown applied - Moonode is now HOME.${NC}"
            if [ "$IS_XIAOMI" -eq 1 ]; then
                echo -e "${YELLOW}Xiaomi note: MIUI re-enables the stock launcher on reboot.${NC}"
                echo -e "${YELLOW}Rebuild the APK (BootReceiver Xiaomi retries) for persistent boot behaviour.${NC}"
            fi
        else
            echo -e "${RED}Lockdown failed - re-enabling stock launcher for safety.${NC}"
            $ADB_CMD shell pm enable com.google.android.apps.tv.launcherx 2>/dev/null || true
            $ADB_CMD shell pm enable com.google.android.tungsten.setupwraith 2>/dev/null || true
            $ADB_CMD shell pm enable com.google.android.tvlauncher 2>/dev/null || true
        fi
    else
        echo -e "${RED}Moonode is not on screen ($FOCUS) - skipping lockdown.${NC}"
        echo "  Launch Moonode manually, then re-run with --lockdown."
    fi
    echo ""
fi

# Final instructions
echo -e "${GREEN}=================================="
echo -e "🎉 Setup Complete!"
echo -e "==================================${NC}"
echo ""
echo "What's configured ($DEVICE_KIND):"
echo "  ✓ Moonode Launcher installed"
echo "  ✓ Captive-portal probe disabled (Service Worker can register)"
if [ "$IS_FIRETV" -eq 1 ]; then
    echo "  ✓ Amazon launcher(s) disabled"
    echo "  ✓ HOME Guardian enabled + self-healing (via WRITE_SECURE_SETTINGS)"
    echo "  ✓ Fire OS Energy Saver / EcoMode neutralised"
    echo "  ✓ Fire TV auto-updates suppressed (apps + forced OTAs)"
else
    echo "  ✓ Google Backdrop ambient-dream disabled (no black-screen-after-boot)"
    if [ "$SOFT_MODE" -eq 1 ] && [ "$LOCKDOWN_APPLIED" -eq 0 ]; then
        echo "  ✓ Soft mode: stock launcher LEFT ENABLED (recovery path preserved)"
        if moonode_is_default_home 2>/dev/null || [ "$NEW_HOME" = "com.moonode.launcher" ]; then
            echo "  ✓ Moonode is default HOME role (Xiaomi picker / role manager)"
            echo "  ! Stock launcher still wins HOME button - re-run with --lockdown"
        else
            echo "  ! Stock launcher is still HOME - finish picker step on TV to switch"
        fi
    elif [ "$LOCKDOWN_APPLIED" -eq 1 ]; then
        echo "  ✓ Lockdown applied: stock launcher disabled, Moonode is HOME"
    elif [ "$SOFT_MODE" -eq 1 ]; then
        echo "  ✓ Soft mode: stock launcher LEFT ENABLED (recovery path preserved)"
    else
        echo "  ✓ Moonode set as HOME activity"
    fi
    echo "  ✓ Screensaver / sleep / DayDream disabled"
    echo "  ✓ App auto-update + automatic OTAs suppressed"
fi
echo "  ✓ Display overscan reset (full screen)"
echo "  ✓ Service Worker cache warmed (offline reboot ready)"
echo ""

if [ "$SOFT_MODE" -eq 1 ] && [ "$LOCKDOWN_APPLIED" -eq 0 ]; then
    echo -e "${YELLOW}Recovery path (soft mode):${NC}"
    echo "  If Moonode ever black-screens, press HOME on the remote - the system"
    echo "  HOME picker will reappear and you can switch back to the stock"
    echo "  launcher with no ADB needed. The stock launcher was NOT disabled."
    if [ "$IS_XIAOMI" -eq 1 ]; then
        echo ""
        echo -e "${YELLOW}To make Moonode actually HOME on Xiaomi:${NC}"
        echo "  1. Rebuild APK:  cd .. && flutter build apk --release"
        echo "  2. Re-run setup: ./setup-moonode-launcher.sh --lockdown IP:5555"
    fi
    echo ""
fi

if [ "$IS_FIRETV" -eq 1 ]; then
    echo -e "${YELLOW}If the screen still goes black after ~4 hours of inactivity:${NC}"
    echo "    Settings → Preferences → Power → Energy Saver → Off"
    echo "  (Some Fire OS builds gate this behind the on-screen UI only.)"
    echo ""
fi

echo "Next steps:"
echo "  1. Press the HOME button on your TV remote"
if [ "$IS_FIRETV" -eq 1 ]; then
    echo "  2. If prompted, select 'Moonode Launcher' and choose 'Always'"
else
    echo "  2. Moonode should already be HOME - no picker should appear"
fi
echo "  3. Let moonode.tv load fully at least once on WiFi (already done by"
echo "     this script's warm-up window, but if you swap APKs do it again)"
echo ""
echo -e "${YELLOW}IMPORTANT: First load requires internet to cache content!${NC}"
echo ""

echo -e "${YELLOW}To restore the original launcher:${NC}"
echo "  ./uninstall-moonode-launcher.sh"
echo "  (or manually re-enable the stock launcher package, see TROUBLESHOOTING.md)"
echo ""
echo -e "${BLUE}🌙 Moonode - From Your Screen to Their Pocket${NC}"
echo ""

