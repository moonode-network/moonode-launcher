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

# Optional: Keep screen always on for kiosk mode
echo -e "${BLUE}Configuring kiosk settings...${NC}"
echo "  Setting screen to never turn off..."
$ADB_CMD shell settings put system screen_off_timeout 2147483647 2>/dev/null || true
echo -e "${GREEN}Kiosk settings configured!${NC}"
echo ""

# Reset overscan to use full screen (no cropping)
echo -e "${BLUE}Configuring display settings...${NC}"
echo "  Resetting overscan to 100% (full screen)..."
$ADB_CMD shell wm overscan 0,0,0,0 2>/dev/null || true
$ADB_CMD shell wm overscan reset 2>/dev/null || true
# Also try setting display density to default
echo "  Resetting display density..."
$ADB_CMD shell wm density reset 2>/dev/null || true
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
echo "  ✓ Screen set to always-on"
echo "  ✓ Display overscan reset (full screen)"
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

