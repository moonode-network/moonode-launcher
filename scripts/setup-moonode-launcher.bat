@echo off
REM
REM Moonode Launcher Setup Script (Windows)
REM
REM Usage: setup-moonode-launcher.bat [DEVICE_IP[:PORT]]
REM
REM Run from the repo root:  scripts\setup-moonode-launcher.bat 192.168.1.100
REM

echo.
echo   Moonode Launcher Setup
echo   ==================================
echo.

REM Check if ADB is installed
where adb >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo   [ERROR] ADB is not installed or not in PATH
    echo.
    echo   Download Android SDK Platform Tools from:
    echo   https://developer.android.com/tools/releases/platform-tools
    echo.
    echo   Extract it and add the folder to your system PATH.
    echo.
    pause
    exit /b 1
)

REM Start ADB daemon
echo   Checking ADB daemon...
adb start-server >nul 2>&1

REM Connect to device if IP provided
if "%~1"=="" goto :skip_connect

echo   Connecting to device at %~1...
adb connect %~1
timeout /t 2 /nobreak >nul

:skip_connect

REM Check device connection
echo   Checking device connection...
adb devices | findstr /r "device$" >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo.
    echo   [ERROR] No devices connected
    echo.
    echo   Options:
    echo     1. Connect via WiFi:  setup-moonode-launcher.bat IP_ADDRESS:5555
    echo     2. Connect via USB:   setup-moonode-launcher.bat
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
echo   Device info:
adb shell getprop ro.product.model
adb shell getprop ro.build.version.release
echo.

REM Find APK - look in repo root first, then build folder
set "SCRIPT_DIR=%~dp0"
set "REPO_ROOT=%SCRIPT_DIR%..\"

set "APK_FOUND=0"
if exist "%REPO_ROOT%moonode-launcher.apk" (
    set "APK_PATH=%REPO_ROOT%moonode-launcher.apk"
    set "APK_FOUND=1"
)
if "%APK_FOUND%"=="0" (
    if exist "%REPO_ROOT%build\app\outputs\flutter-apk\app-release.apk" (
        set "APK_PATH=%REPO_ROOT%build\app\outputs\flutter-apk\app-release.apk"
        set "APK_FOUND=1"
    )
)

if "%APK_FOUND%"=="0" (
    echo   [ERROR] APK not found!
    echo.
    echo   Please place moonode-launcher.apk in the repo root folder.
    echo.
    pause
    exit /b 1
)

REM Install Moonode Launcher
echo   Installing Moonode Launcher...
adb install -r "%APK_PATH%"
if %ERRORLEVEL% neq 0 (
    echo   [ERROR] Failed to install APK
    pause
    exit /b 1
)
echo   Moonode Launcher installed!
echo.

REM Disable known launchers
echo   Disabling default launchers...
adb shell pm disable-user --user 0 com.google.android.apps.tv.launcherx >nul 2>&1
adb shell pm disable-user --user 0 com.google.android.tvlauncher >nul 2>&1
adb shell pm disable-user --user 0 com.google.android.leanbacklauncher >nul 2>&1
adb shell pm disable-user --user 0 com.google.android.tungsten.setupwraith >nul 2>&1
adb shell pm disable-user --user 0 com.amazon.tv.launcher >nul 2>&1
adb shell pm disable-user --user 0 com.amazon.tv.leanbacklauncher >nul 2>&1
adb shell pm disable-user --user 0 com.amazon.tv.leanbacklauncher.widget >nul 2>&1
echo   Default launchers disabled!
echo.

REM Disable captive portal detection
echo   Configuring offline mode...
adb shell settings put global captive_portal_mode 0 >nul 2>&1
adb shell settings put global captive_portal_detection_enabled 0 >nul 2>&1
adb shell settings put global wifi_watchdog_on 0 >nul 2>&1
echo   Offline mode configured!
echo.

REM Keep screen always on
echo   Configuring kiosk settings...
adb shell settings put system screen_off_timeout 2147483647 >nul 2>&1
echo   Kiosk settings configured!
echo.

REM Reset overscan
echo   Configuring display settings...
adb shell wm overscan 0,0,0,0 >nul 2>&1
adb shell wm overscan reset >nul 2>&1
adb shell wm density reset >nul 2>&1
echo   Display settings configured!
echo.

REM Verify installation
echo   Verifying installation...
adb shell pm list packages | findstr "com.moonode.launcher" >nul 2>&1
if %ERRORLEVEL% equ 0 (
    echo   Moonode Launcher is installed!
) else (
    echo   [ERROR] Moonode Launcher not found
    pause
    exit /b 1
)

echo.
echo   ==================================
echo   Setup Complete!
echo   ==================================
echo.
echo   Next steps:
echo     1. Press HOME on your TV remote
echo     2. If prompted, select 'Moonode Launcher'
echo     3. Choose 'Always' to make it permanent
echo     4. Connect to WiFi and let moonode.tv load
echo.
echo   IMPORTANT: First load requires internet to cache content!
echo.
echo   To restore original launcher:
echo     adb shell pm enable com.google.android.apps.tv.launcherx
echo     adb shell pm enable com.google.android.tungsten.setupwraith
echo.

pause
