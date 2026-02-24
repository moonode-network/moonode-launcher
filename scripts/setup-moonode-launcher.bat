@echo off
REM
REM Moonode Launcher Setup Script (Windows)
REM This script installs and configures Moonode Launcher as the default HOME screen
REM
REM Usage: setup-moonode-launcher.bat [DEVICE_IP[:PORT]]
REM
REM Examples:
REM   setup-moonode-launcher.bat                      Use USB connection
REM   setup-moonode-launcher.bat 192.168.1.100       Connect via WiFi (default port 5555)
REM   setup-moonode-launcher.bat 192.168.1.100:5555  Connect via WiFi (explicit port)
REM

setlocal enabledelayedexpansion

echo.
echo   Moonode Launcher Setup
echo   ==================================
echo.

REM Check if ADB is installed
where adb >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo   [ERROR] ADB is not installed or not in PATH
    echo   Please install Android SDK Platform Tools:
    echo   https://developer.android.com/tools/releases/platform-tools
    echo.
    echo   After downloading, extract and add the folder to your PATH,
    echo   or place adb.exe in the same folder as this script.
    pause
    exit /b 1
)

REM Check ADB daemon
echo   Checking ADB daemon...
adb devices >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo   ADB daemon not running. Attempting to start...
    adb start-server >nul 2>&1
)

REM Parse IP and port
set "DEVICE_IP="
set "DEVICE_PORT=5555"
set "ADB_CMD=adb"

if not "%~1"=="" (
    set "DEVICE_ADDRESS=%~1"

    REM Check if port is included
    echo %~1 | findstr ":" >nul
    if !ERRORLEVEL! equ 0 (
        for /f "tokens=1,2 delims=:" %%a in ("%~1") do (
            set "DEVICE_IP=%%a"
            set "DEVICE_PORT=%%b"
        )
    ) else (
        set "DEVICE_IP=%~1"
    )

    echo   Connecting to device at !DEVICE_IP!:!DEVICE_PORT!...
    adb connect !DEVICE_IP!:!DEVICE_PORT!

    REM Wait for connection
    timeout /t 2 /nobreak >nul

    set "ADB_CMD=adb -s !DEVICE_IP!:!DEVICE_PORT!"
)

REM Check device connection
echo   Checking device connection...
set "DEVICE_COUNT=0"
for /f %%i in ('!ADB_CMD! devices 2^>nul ^| findstr /r "device$" ^| find /c /v ""') do set "DEVICE_COUNT=%%i"

if !DEVICE_COUNT! equ 0 (
    echo.
    echo   [ERROR] No devices connected
    echo.
    echo   Available options:
    echo     1. Connect device via USB and run: setup-moonode-launcher.bat
    echo     2. Connect via WiFi: setup-moonode-launcher.bat IP_ADDRESS
    echo.
    echo   Current ADB devices:
    adb devices
    echo.
    pause
    exit /b 1
)

echo   Device connected!
echo.

REM Get device info
for /f "tokens=*" %%a in ('!ADB_CMD! shell getprop ro.product.model') do set "DEVICE_MODEL=%%a"
for /f "tokens=*" %%a in ('!ADB_CMD! shell getprop ro.build.version.release') do set "ANDROID_VERSION=%%a"
echo   Device: %DEVICE_MODEL%
echo   Android: %ANDROID_VERSION%
echo.

REM Find APK
set "SCRIPT_DIR=%~dp0"
set "REPO_ROOT=%SCRIPT_DIR%.."

set "APK_PATH=%REPO_ROOT%\moonode-launcher.apk"
if not exist "%APK_PATH%" (
    set "APK_PATH=%REPO_ROOT%\build\app\outputs\flutter-apk\app-release.apk"
)
if not exist "%APK_PATH%" (
    echo   [WARN] APK not found. Attempting to build...
    pushd "%REPO_ROOT%"
    flutter build apk --release
    popd
    set "APK_PATH=%REPO_ROOT%\build\app\outputs\flutter-apk\app-release.apk"
)
if not exist "%APK_PATH%" (
    echo   [ERROR] APK not found and build failed.
    echo   Please install Flutter or place moonode-launcher.apk in the repo root.
    pause
    exit /b 1
)

REM Install Moonode Launcher
echo   Installing Moonode Launcher...
!ADB_CMD! install -r "%APK_PATH%"
if %ERRORLEVEL% neq 0 (
    echo   [ERROR] Failed to install APK
    pause
    exit /b 1
)
echo   Moonode Launcher installed!
echo.

REM Disable known launchers
echo   Disabling default launchers...

set "LAUNCHERS=com.google.android.apps.tv.launcherx com.google.android.tvlauncher com.google.android.leanbacklauncher com.google.android.tungsten.setupwraith com.amazon.tv.launcher com.amazon.tv.leanbacklauncher com.amazon.tv.leanbacklauncher.widget"

for %%L in (%LAUNCHERS%) do (
    !ADB_CMD! shell pm list packages 2>nul | findstr "%%L" >nul
    if !ERRORLEVEL! equ 0 (
        echo     Disabling %%L...
        !ADB_CMD! shell pm disable-user --user 0 %%L >nul 2>&1
    )
)

echo   Default launchers disabled!
echo.

REM Disable captive portal detection
echo   Configuring offline mode...
echo     Disabling 'WiFi has no internet' warnings...
!ADB_CMD! shell settings put global captive_portal_mode 0 >nul 2>&1
!ADB_CMD! shell settings put global captive_portal_detection_enabled 0 >nul 2>&1
!ADB_CMD! shell settings put global wifi_watchdog_on 0 >nul 2>&1
echo   Offline mode configured!
echo.

REM Keep screen always on
echo   Configuring kiosk settings...
echo     Setting screen to never turn off...
!ADB_CMD! shell settings put system screen_off_timeout 2147483647 >nul 2>&1
echo   Kiosk settings configured!
echo.

REM Reset overscan
echo   Configuring display settings...
echo     Resetting overscan to 100%% (full screen)...
!ADB_CMD! shell wm overscan 0,0,0,0 >nul 2>&1
!ADB_CMD! shell wm overscan reset >nul 2>&1
echo     Resetting display density...
!ADB_CMD! shell wm density reset >nul 2>&1
echo   Display settings configured!
echo.

REM Verify installation
echo   Verifying installation...
!ADB_CMD! shell pm list packages 2>nul | findstr "com.moonode.launcher" >nul
if %ERRORLEVEL% equ 0 (
    echo   Moonode Launcher is installed
) else (
    echo   [ERROR] Moonode Launcher not found
    pause
    exit /b 1
)

REM Done
echo.
echo   ==================================
echo   Setup Complete!
echo   ==================================
echo.
echo   What's configured:
echo     * Moonode Launcher installed
echo     * Default launcher disabled
echo     * 'No Internet' warnings disabled
echo     * Screen set to always-on
echo     * Display overscan reset (full screen)
echo.
echo   Next steps:
echo     1. Press the HOME button on your TV remote
echo     2. If prompted, select 'Moonode Launcher'
echo     3. Choose 'Always' to make it permanent
echo     4. Connect to WiFi and let moonode.tv load (caches for offline)
echo.
echo   IMPORTANT: First load requires internet to cache content!
echo.
echo   To restore original launcher:
echo     adb shell pm enable com.google.android.apps.tv.launcherx
echo     adb shell pm enable com.google.android.tungsten.setupwraith
echo     adb shell settings put global captive_portal_mode 1
echo.
echo   Moonode - From Your Screen to Their Pocket
echo.

pause
