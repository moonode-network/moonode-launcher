Yes, Fire Stick is Android-based (Fire OS), so the same ADB commands work. The only differences:

**Timezone** -- same command, works on Fire Stick:

```bash
adb shell setprop persist.sys.timezone America/Montreal
```

**Moonode Launcher** -- the setup script already handles Fire TV. Look at line 181 of your setup script:

```181:181:/Users/zeiv/Desktop/infrastructure/moonode-launcher/scripts/setup-moonode-launcher.sh
    "com.amazon.tv.launcher"                       # Fire TV
```

**Connecting to Fire Stick via ADB** is slightly different though:

1. Go to **Settings > My Fire TV > Developer Options**
2. Enable **ADB Debugging**
3. Enable **Apps from Unknown Sources**
4. Find the IP: **Settings > My Fire TV > About > Network**
5. Connect:

```bash
adb connect <FIRESTICK_IP>:5555
```

Then run the full setup:

```bash
cd /Users/zeiv/Desktop/infrastructure/moonode-launcher
./scripts/setup-moonode-launcher.sh <FIRESTICK_IP>
```

**One caveat**: On newer Fire OS versions (Fire OS 7+), Amazon is more aggressive about re-enabling their launcher. If the Fire Stick restores the Amazon launcher after a reboot, you may also need to disable:

```bash
adb shell pm disable-user --user 0 com.amazon.tv.launcher
adb shell pm disable-user --user 0 com.amazon.tv.leanbacklauncher
adb shell pm disable-user --user 0 com.amazon.tv.leanbacklauncher.widget
```

So yes, it works -- Fire Stick is actually one of the more popular devices for this kind of kiosk setup.
