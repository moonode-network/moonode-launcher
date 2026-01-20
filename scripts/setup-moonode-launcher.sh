#!/bin/bash
#
# Moonode Launcher Setup Script
# This script installs and configures Moonode Launcher as the default HOME screen
#
# Usage: ./setup-moonode-launcher.sh [DEVICE_IP]
#
# Examples:
#   ./setup-moonode-launcher.sh                    # Use USB connection
#   ./setup-moonode-launcher.sh 192.168.1.100     # Connect via WiFi
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

# Connect to device if IP provided
if [ -n "$1" ]; then
    echo -e "${BLUE}Connecting to device at $1...${NC}"
    adb connect "$1:5555" || {
        echo -e "${RED}Failed to connect to $1${NC}"
        echo "Make sure:"
        echo "  1. Developer options are enabled on the device"
        echo "  2. USB debugging is enabled"
        echo "  3. Network debugging is enabled (for WiFi connection)"
        exit 1
    }
fi

# Check device connection
echo -e "${BLUE}Checking device connection...${NC}"
DEVICE_COUNT=$(adb devices | grep -c "device$" || true)
if [ "$DEVICE_COUNT" -eq 0 ]; then
    echo -e "${RED}No devices connected${NC}"
    echo "Connect your device via USB or run with IP address"
    exit 1
fi

echo -e "${GREEN}Device connected!${NC}"
echo ""

# Get device info
DEVICE_MODEL=$(adb shell getprop ro.product.model | tr -d '\r')
ANDROID_VERSION=$(adb shell getprop ro.build.version.release | tr -d '\r')
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
adb install -r "$APK_PATH" || {
    echo -e "${RED}Failed to install APK${NC}"
    exit 1
}
echo -e "${GREEN}Moonode Launcher installed!${NC}"
echo ""

# Detect current default launcher
echo -e "${BLUE}Detecting current launcher...${NC}"
CURRENT_LAUNCHER=$(adb shell cmd package resolve-activity -a android.intent.action.MAIN -c android.intent.category.HOME | grep packageName | head -1 | cut -d'=' -f2 | tr -d '\r')
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
    if adb shell pm list packages | grep -q "$launcher"; then
        echo "  Disabling $launcher..."
        adb shell pm disable-user --user 0 "$launcher" 2>/dev/null || true
    fi
done

# Also disable the detected current launcher if different
if [ -n "$CURRENT_LAUNCHER" ] && [ "$CURRENT_LAUNCHER" != "com.moonode.launcher" ]; then
    echo "  Disabling $CURRENT_LAUNCHER..."
    adb shell pm disable-user --user 0 "$CURRENT_LAUNCHER" 2>/dev/null || true
fi

echo -e "${GREEN}Default launchers disabled!${NC}"
echo ""

# Disable captive portal detection (prevents "No Internet" warnings)
echo -e "${BLUE}Configuring offline mode...${NC}"
echo "  Disabling 'WiFi has no internet' warnings..."
adb shell settings put global captive_portal_mode 0 2>/dev/null || true
adb shell settings put global captive_portal_detection_enabled 0 2>/dev/null || true
adb shell settings put global wifi_watchdog_on 0 2>/dev/null || true
echo -e "${GREEN}Offline mode configured!${NC}"
echo ""

# Optional: Keep screen always on for kiosk mode
echo -e "${BLUE}Configuring kiosk settings...${NC}"
echo "  Setting screen to never turn off..."
adb shell settings put system screen_off_timeout 2147483647 2>/dev/null || true
echo -e "${GREEN}Kiosk settings configured!${NC}"
echo ""

# Verify Moonode is installed
echo -e "${BLUE}Verifying installation...${NC}"
if adb shell pm list packages | grep -q "com.moonode.launcher"; then
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
echo "  ✓ Screen set to always-on"
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

