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

---

## Flicker / brief black flashes on customer TVs

**Symptom**: Fire Stick flickers (~0.5 s black flash) on every UI step — opening
Settings, navigating menus, when an overlay ad appears, when a video starts /
ends. Sometimes the customer describes it as "the screen blinks every few
seconds".

**Important**: if **system Settings flickers too** (i.e. without the launcher
even being on screen), this is **not a Moonode bug**. The launcher / WebView
cannot affect how the Fire OS system UI renders. The cause is at the HDMI /
display-mode layer, not the application.

### Why it happens

Fire OS ships with two display options that **re-handshake the HDMI
signal every time on-screen content type changes**:

| Setting | What it does | Why it causes flicker |
|---|---|---|
| **Match Original Frame Rate** | Switches HDMI output between 24 / 30 / 50 / 60 Hz to match the source frame rate of whatever's on screen | Every navigation between UI (60 Hz) and a video ad (often 30 Hz source) triggers a refresh-rate switch. Each switch is a TMDS clock change → TV does an HDMI re-sync → ~500 ms black screen. |
| **Match Dynamic Range** | Switches HDMI output between SDR / HDR10 to match content metadata | Same idea — overlay ad starts (HDR10 metadata, even if content is SDR-mastered) → output renegotiates → black flash. |

For signage these are the wrong defaults. We want a **fixed** HDMI signal at
all times so the TV never re-syncs.

### Fix (do this on every customer install — takes 30 s)

1. **Hardware first**: plug the Fire Stick **directly into the TV's HDMI port**.
   Skip the HDMI extender that ships in the box — it's a passive coupler with
   poor TMDS shielding and causes micro-flickers on its own. If form factor
   forces an extender, use an active HDMI 2.0 extender (look for "HDCP 2.2
   passthrough" branding), not the bundled passive one.

2. **System UI**: Settings → Display & Sounds → Display
   - **Match Original Frame Rate → OFF**
   - **Match Dynamic Range → OFF** (only present on HDR-capable Fire Sticks)
   - **Display Resolution → fixed value** (1080p 60Hz for non-4K TVs;
     4K UHD 60Hz for 4K TVs that support it natively). Avoid "Auto" — that's
     the option that lets the OS keep switching.
   - **Calibrate Display** if available — pick the option that fills the
     screen cleanly without overscan.

3. **Reboot the Fire Stick** so the new mode locks in cleanly:

   ```bash
   adb reboot
   ```

4. **Verify with ADB** (optional, but useful when the customer's TV doesn't
   surface the GUI options):

   ```bash
   # Current mode in use:
   adb shell dumpsys display | grep -E "mDisplayInfo|RefreshRate" | head -10

   # The two flags that matter — both should be 0:
   adb shell settings get system match_content_frame_rate
   adb shell settings get global match_content_hdr
   ```

   If either returns `1`, force them off:

   ```bash
   adb shell settings put system match_content_frame_rate 0
   adb shell settings put global match_content_hdr 0
   ```

### Other things worth checking if the flicker persists

- **HDMI cable quality** — bargain-bin HDMI cables fail the TMDS clock spec
  on long runs. Shouldn't matter for a Fire Stick directly seated in the TV,
  but if the customer is using a wall-plate HDMI connector + 2 m run, that
  cable is suspect.
- **TV input port** — port 1 is often the "ARC" / CEC port with stricter
  handshake; ports 2/3/4 are dumber and more stable. Try moving inputs.
- **HDR auto-trigger from the TV**, not the Fire Stick — some Sony / TCL
  panels enter HDR mode on their own when they see HDR-flagged content even
  if the source is SDR. The TV's own picture settings menu has the toggle:
  look for "HDMI Mode" / "HDMI Format" → set to "Standard" (not "Enhanced" or
  "Auto"). Customer-side; we can't fix it from ADB.

### What this section is **not**

This is HDMI / display-layer flicker. It is **not** the GIF-overlay-flicker
issue (where a GIF restarts from frame 0 on every appearance — that one would
be a React re-mount and lives in `frontend-player`, not the launcher). If
the customer reports a flicker that **only** happens on overlay ads with GIFs
(and not in system Settings), reach for `frontend-player/src/components/
OverlayAdvertising/` and instrument with Chrome DevTools, not for these
display settings.

### One-liner pre-install ADB checklist for the technician

Paste this on the laptop after `adb connect <fireStickIp>:5555` and before
running the launcher setup script — turns off both auto-switchers in one go:

```bash
adb shell settings put system match_content_frame_rate 0 \
  && adb shell settings put global match_content_hdr 0 \
  && adb shell input keyevent KEYCODE_HOME \
  && echo "Display auto-switching disabled. Reboot Fire Stick to confirm."
```
