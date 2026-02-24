#
# Moonode Launcher Setup Script (Windows PowerShell)
# This script installs and configures Moonode Launcher as the default HOME screen
#
# Usage: .\setup-moonode-launcher.ps1 [DEVICE_IP[:PORT]]
#
# Examples:
#   .\setup-moonode-launcher.ps1                      # Use USB connection
#   .\setup-moonode-launcher.ps1 192.168.1.100       # Connect via WiFi (default port 5555)
#   .\setup-moonode-launcher.ps1 192.168.1.100:5555  # Connect via WiFi (explicit port)
#

param(
    [string]$DeviceAddress
)

$ErrorActionPreference = "Stop"

function Write-Status($msg)  { Write-Host "  $msg" -ForegroundColor Cyan }
function Write-Success($msg) { Write-Host "  $msg" -ForegroundColor Green }
function Write-Warn($msg)    { Write-Host "  $msg" -ForegroundColor Yellow }
function Write-Err($msg)     { Write-Host "  $msg" -ForegroundColor Red }

Write-Host ""
Write-Host "  Moonode Launcher Setup" -ForegroundColor Yellow
Write-Host "  ==================================" -ForegroundColor Yellow
Write-Host ""

# Check if ADB is installed
try {
    $null = Get-Command adb -ErrorAction Stop
} catch {
    Write-Err "Error: ADB is not installed or not in PATH"
    Write-Host "  Please install Android SDK Platform Tools:"
    Write-Host "  https://developer.android.com/tools/releases/platform-tools"
    exit 1
}

# Check ADB daemon
Write-Status "Checking ADB daemon..."
$null = adb devices 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Warn "ADB daemon not running. Attempting to start..."
    adb start-server 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Failed to start ADB daemon"
        exit 1
    }
}

# Parse IP and optional port
$DeviceIP = ""
$DevicePort = "5555"

if ($DeviceAddress) {
    if ($DeviceAddress -match ":") {
        $parts = $DeviceAddress -split ":"
        $DeviceIP = $parts[0]
        $DevicePort = $parts[1]
    } else {
        $DeviceIP = $DeviceAddress
    }

    Write-Status "Connecting to device at ${DeviceIP}:${DevicePort}..."
    $connectResult = adb connect "${DeviceIP}:${DevicePort}" 2>&1
    Write-Host "  $connectResult"

    if ($connectResult -match "(refused|failed|unable|cannot|error)") {
        Write-Host ""
        Write-Err "Failed to connect to ${DeviceIP}:${DevicePort}"
        Write-Host ""
        Write-Warn "Troubleshooting steps:"
        Write-Host "  1. Make sure the device is on the same WiFi network"
        Write-Host "  2. Enable Developer Options on the device:"
        Write-Host "     - Settings > About > Tap 'Build number' 7 times"
        Write-Host "  3. Enable USB debugging:"
        Write-Host "     - Settings > Developer Options > USB debugging"
        Write-Host "  4. Enable Wireless debugging (Android 11+):"
        Write-Host "     - Settings > Developer Options > Wireless debugging > Enable"
        Write-Host "  5. For older Android versions, connect via USB first and run:"
        Write-Host "     - adb tcpip $DevicePort"
        Write-Host ""
        exit 1
    }

    Start-Sleep -Seconds 2
}

# Determine ADB command prefix
if ($DeviceIP) {
    $DeviceSerial = "${DeviceIP}:${DevicePort}"
    $adbPrefix = @("adb", "-s", $DeviceSerial)
} else {
    $deviceLines = (adb devices 2>$null) | Select-String "`tdevice$"
    $deviceCount = @($deviceLines).Count

    if ($deviceCount -gt 1) {
        Write-Err "Multiple devices connected"
        Write-Host ""
        Write-Host "  Please specify which device to use:"
        adb devices
        Write-Host ""
        Write-Host "  Run with IP address: .\setup-moonode-launcher.ps1 IP_ADDRESS"
        exit 1
    }

    $adbPrefix = @("adb")
}

function Invoke-Adb {
    param([string[]]$Args)
    & $adbPrefix[0] ($adbPrefix[1..($adbPrefix.Length)] + $Args) 2>$null
}

# Check device connection
Write-Status "Checking device connection..."
$deviceLines = (& $adbPrefix[0] ($adbPrefix[1..($adbPrefix.Length)] + @("devices")) 2>$null) | Select-String "`tdevice$"
$deviceCount = @($deviceLines).Count

if ($deviceCount -eq 0) {
    Write-Err "No devices connected"
    Write-Host ""
    Write-Host "  Available options:"
    Write-Host "    1. Connect device via USB and run: .\setup-moonode-launcher.ps1"
    Write-Host "    2. Connect via WiFi: .\setup-moonode-launcher.ps1 IP_ADDRESS[:PORT]"
    Write-Host ""
    exit 1
}

Write-Success "Device connected!"
Write-Host ""

# Get device info
$deviceModel = (Invoke-Adb @("shell", "getprop", "ro.product.model")).Trim()
$androidVersion = (Invoke-Adb @("shell", "getprop", "ro.build.version.release")).Trim()
Write-Host "  Device: $deviceModel"
Write-Host "  Android: $androidVersion"
Write-Host ""

# Find APK
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir

$apkPath = Join-Path $repoRoot "moonode-launcher.apk"
if (-not (Test-Path $apkPath)) {
    $apkPath = Join-Path $repoRoot "build\app\outputs\flutter-apk\app-release.apk"
}
if (-not (Test-Path $apkPath)) {
    Write-Warn "APK not found. Attempting to build..."
    Push-Location $repoRoot
    flutter build apk --release
    $apkPath = Join-Path $repoRoot "build\app\outputs\flutter-apk\app-release.apk"
    Pop-Location
}

if (-not (Test-Path $apkPath)) {
    Write-Err "APK not found and build failed. Please install Flutter or place moonode-launcher.apk in the repo root."
    exit 1
}

# Install Moonode Launcher
Write-Status "Installing Moonode Launcher..."
Invoke-Adb @("install", "-r", $apkPath)
if ($LASTEXITCODE -ne 0) {
    Write-Err "Failed to install APK"
    exit 1
}
Write-Success "Moonode Launcher installed!"
Write-Host ""

# Detect current default launcher
Write-Status "Detecting current launcher..."
$resolveOutput = Invoke-Adb @("shell", "cmd", "package", "resolve-activity", "-a", "android.intent.action.MAIN", "-c", "android.intent.category.HOME")
$currentLauncher = ($resolveOutput | Select-String "packageName") -replace '.*packageName=', '' | Select-Object -First 1
$currentLauncher = $currentLauncher.Trim()
Write-Host "  Current launcher: $currentLauncher"
Write-Host ""

# Known launcher packages to disable
$launchersToDisable = @(
    "com.google.android.apps.tv.launcherx",
    "com.google.android.tvlauncher",
    "com.google.android.leanbacklauncher",
    "com.google.android.tungsten.setupwraith",
    "com.amazon.tv.launcher",
    "com.amazon.tv.leanbacklauncher",
    "com.amazon.tv.leanbacklauncher.widget"
)

# Disable known launchers
Write-Status "Disabling default launchers..."
$installedPackages = Invoke-Adb @("shell", "pm", "list", "packages")
foreach ($launcher in $launchersToDisable) {
    if ($installedPackages -match $launcher) {
        Write-Host "    Disabling $launcher..."
        Invoke-Adb @("shell", "pm", "disable-user", "--user", "0", $launcher) | Out-Null
    }
}

# Also disable the detected current launcher if different
if ($currentLauncher -and $currentLauncher -ne "com.moonode.launcher") {
    Write-Host "    Disabling $currentLauncher..."
    Invoke-Adb @("shell", "pm", "disable-user", "--user", "0", $currentLauncher) | Out-Null
}

Write-Success "Default launchers disabled!"
Write-Host ""

# Disable captive portal detection
Write-Status "Configuring offline mode..."
Write-Host "    Disabling 'WiFi has no internet' warnings..."
Invoke-Adb @("shell", "settings", "put", "global", "captive_portal_mode", "0") | Out-Null
Invoke-Adb @("shell", "settings", "put", "global", "captive_portal_detection_enabled", "0") | Out-Null
Invoke-Adb @("shell", "settings", "put", "global", "wifi_watchdog_on", "0") | Out-Null
Write-Success "Offline mode configured!"
Write-Host ""

# Keep screen always on
Write-Status "Configuring kiosk settings..."
Write-Host "    Setting screen to never turn off..."
Invoke-Adb @("shell", "settings", "put", "system", "screen_off_timeout", "2147483647") | Out-Null
Write-Success "Kiosk settings configured!"
Write-Host ""

# Reset overscan
Write-Status "Configuring display settings..."
Write-Host "    Resetting overscan to 100% (full screen)..."
Invoke-Adb @("shell", "wm", "overscan", "0,0,0,0") | Out-Null
Invoke-Adb @("shell", "wm", "overscan", "reset") | Out-Null
Write-Host "    Resetting display density..."
Invoke-Adb @("shell", "wm", "density", "reset") | Out-Null
Write-Success "Display settings configured!"
Write-Host ""

# Verify installation
Write-Status "Verifying installation..."
$packages = Invoke-Adb @("shell", "pm", "list", "packages")
if ($packages -match "com.moonode.launcher") {
    Write-Success "Moonode Launcher is installed"
} else {
    Write-Err "Moonode Launcher not found"
    exit 1
}

# Done
Write-Host ""
Write-Host "  ==================================" -ForegroundColor Green
Write-Host "  Setup Complete!" -ForegroundColor Green
Write-Host "  ==================================" -ForegroundColor Green
Write-Host ""
Write-Host "  What's configured:"
Write-Host "    * Moonode Launcher installed"
Write-Host "    * Default launcher disabled"
Write-Host "    * 'No Internet' warnings disabled"
Write-Host "    * Screen set to always-on"
Write-Host "    * Display overscan reset (full screen)"
Write-Host ""
Write-Host "  Next steps:"
Write-Host "    1. Press the HOME button on your TV remote"
Write-Host "    2. If prompted, select 'Moonode Launcher'"
Write-Host "    3. Choose 'Always' to make it permanent"
Write-Host "    4. Connect to WiFi and let moonode.tv load (caches for offline)"
Write-Host ""
Write-Warn "IMPORTANT: First load requires internet to cache content!"
Write-Host ""
Write-Warn "To restore original launcher:"
Write-Host "  adb shell pm enable com.google.android.apps.tv.launcherx"
Write-Host "  adb shell pm enable com.google.android.tungsten.setupwraith"
Write-Host "  adb shell settings put global captive_portal_mode 1"
Write-Host ""
Write-Host "  Moonode - From Your Screen to Their Pocket" -ForegroundColor Cyan
Write-Host ""
