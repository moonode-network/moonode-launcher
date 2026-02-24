# CHANGE TIME ZONE

# Set timezone to Montreal (Eastern Time)

adb shell setprop persist.sys.timezone America/Montreal

# Verify it took effect

adb shell getprop persist.sys.timezone

# Also check what the box thinks the current time is now

adb shell date

# build

flutter build apk --release

# devices

adb devices

# CONNECT

adb connect <IP>:5555

# RUN SCRIPT (macOS / Linux)

./scripts/setup-moonode-launcher.sh

# RUN SCRIPT (Windows - double-click or from cmd)

scripts\setup-moonode-launcher.bat
scripts\setup-moonode-launcher.bat
