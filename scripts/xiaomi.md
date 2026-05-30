# Xiaomi MiTV / Mi Box (MIUI for TV)

Companion to `amazon.md`. Xiaomi's Android TV variant (MIUI for TV) is
significantly more hostile to third-party launchers than vanilla Android TV
or Fire TV. This document captures every workaround the launcher and setup
script ship for it.

If you just want to deploy a Xiaomi box, jump to **Quick start** at the
bottom. The rest of the doc explains *why* each workaround exists so future
maintainers don't accidentally tear them out.

---

## TL;DR

- **Always run the setup script in `--soft` mode first.** The script
  auto-detects Xiaomi (`Build.MANUFACTURER == "Xiaomi"` /
  `BRAND == "mitv*"`) and forces `--soft` even if you don't pass the flag,
  so you don't have to remember.
- **Pick "Moonode Launcher" on the on-screen system HOME picker** when the
  script tells you to. Xiaomi's HOME-role assignment is set via the system
  Role Manager, not via `cmd package set-home-activity`, so the *user* has
  to confirm.
- **Re-run with `--lockdown` once you've confirmed Moonode runs** to
  disable the stock launcher and the Mi Box's "Recents" pop-up. Skip this
  step on your dev box; it's required for production kiosks.
- **Don't expect the stock launcher to stay disabled across factory
  resets.** MIUI re-enables `com.mitv.tvhome.atv` on every OTA. The
  launcher's `BootReceiver` and `LauncherKeepAliveService` exist so that
  even when Xiaomi briefly wins the HOME race, Moonode comes back to the
  foreground within ~3 s and stays there.

---

## What's different about Xiaomi

### 1. Stock launcher cannot be disabled at install time

On Fire TV and AOSP Android TV, the script's
`pm disable-user --user 0 <stock_launcher_pkg>` makes Moonode the sole
HOME-resolver. On Xiaomi MiTV, doing this **before** Moonode is verified
running results in:

```
Black screen on next reboot.
No HOME activity available.
Device unrecoverable without ADB or factory reset.
```

The stock Xiaomi launcher (`com.mitv.tvhome.atv`) is registered as a
system package, and disabling it without a working third-party HOME means
the framework has no `category.HOME` activity to resolve. Settings won't
auto-launch, and the TV input won't reset itself either.

**Mitigation.** The setup script never disables a Xiaomi launcher in
`--soft` mode, and `IS_XIAOMI=1` forces `--soft`. Lockdown happens only
after the script has resolved Moonode as HOME.

### 2. Default-HOME assignment is owned by Role Manager, not the package manager

On vanilla Android TV:

```bash
adb shell cmd package set-home-activity com.moonode.launcher/.MainActivity
# → activity becomes default-HOME immediately
adb shell cmd package resolve-activity --brief -c android.intent.category.HOME
# → com.moonode.launcher/.MainActivity
```

On MIUI for TV, the same commands run cleanly but **don't take effect** —
`resolve-activity` keeps reporting `com.mitv.tvhome.atv`. The actual
default-HOME state lives in the Role Manager:

```bash
adb shell dumpsys role | sed -n '/role:android.app.role.HOME/,/role:/p'
```

Look for `holders=[com.moonode.launcher]`. That's the source of truth on
Xiaomi.

**Mitigation.** `setup-moonode-launcher.sh::moonode_is_default_home()`
checks both `cmd package resolve-activity` (Fire TV / AOSP) **and**
`dumpsys role` (Xiaomi). When the Role Manager is the only one that
agrees, the script is happy.

### 3. Setting HOME is a user action, not a script action

Because Role Manager is involved, only the *user* can grant the HOME role
on Xiaomi. The script can't do it. What it does instead:

1. Prints a banner: `Now press the Mi remote's HOME button. The system
   should pop a "Choose home app" sheet — pick "Moonode Launcher".`
2. Polls `dumpsys role` every second for up to 5 minutes waiting for the
   role to flip.
3. Once it flips, it continues with the rest of the configuration.

If the device is already paired and Moonode isn't yet HOME on the TV,
that prompt is the *only* way forward. Don't try to bypass it with
`set-home-activity` — see point 2.

### 4. MIUI aggressively kills backgrounded apps

The instant the operator opens Settings (e.g. to change Wi-Fi), MIUI
reaps the launcher process. When the operator returns, the WebView is
re-instantiated from scratch, the SW Cache API rehydrates from disk, the
JS bundle re-evaluates, and the operator sees "loading…" for 1-3 seconds
on every return.

Worse: `clearTaskOnLaunch="true"` and `stateNotNeeded="true"` on
`MainActivity` (carried over from the FLauncher fork) accelerated this on
Xiaomi specifically — the system would drop the WebView's in-memory state
even when the process *did* survive backgrounding.

**Mitigations** (all in this codebase, do not remove on Xiaomi devices):

- `LauncherKeepAliveService` — a foreground service that promotes the
  launcher process to FOREGROUND_SERVICE priority. MIUI's task killer
  treats apps with an active FGS as "in use" and stops reaping them. The
  notification is `IMPORTANCE_MIN`, silent, and `VISIBILITY_SECRET`, so
  the operator never sees it.
- `clearTaskOnLaunch` and `stateNotNeeded` were *removed* from
  `MainActivity` in the manifest. With `launchMode="singleTask"` the back
  stack already has a single activity, so the flag was a no-op for stack
  pruning — but the side-effect was discarding the WebView's in-memory
  state on every HOME press.
- `BootReceiver` schedules an extra `XIAOMI_RETRY_DELAYS_MS` series of
  `startActivity` calls after `BOOT_COMPLETED` (and `LOCKED_BOOT_COMPLETED`),
  conditional on Moonode not already being foreground. This wins the boot
  race against `com.mitv.tvhome.atv` without bouncing back to the launcher
  while the operator is in Settings (`MainActivity.isHomeNavigationPaused()`
  guards retries during a Settings session).

### 5. Android 14 + foregroundServiceType=specialUse needs the matching permission

`targetSdk=34` requires
`android.permission.FOREGROUND_SERVICE_SPECIAL_USE` whenever the manifest
declares `foregroundServiceType="specialUse"`. Without it, the service
crashes the process with a `SecurityException` on `startForeground()`,
which on a HOME launcher means an instant restart loop.

The permission is declared in `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

`LauncherKeepAliveService.onCreate` also wraps `startForeground` in
try/catch + `stopSelf()` on failure so a future OEM permission tightening
won't crash-loop the launcher again — it'll just degrade to non-FGS
priority.

### 6. The Mi remote has no MENU / SETTINGS / F1 / F2 button

Xiaomi sells stripped-down remotes with only HOME, BACK, volume, mic, and
Netflix/YouTube hotkeys. Operators can't reach Android Settings the same
way they can on a Fire TV remote. The launcher exposes two escape hatches
on Xiaomi (gated *off* on Fire TV — see comment in `MainActivity.kt`
about not breaking Alexa):

- **3× BACK within 3 s → opens Android Settings.** Implemented in
  `dispatchKeyEvent`. Triple-press inside the 3-second window is rare
  enough not to fire during normal nav (the in-page router eats single
  / double BACK presses before they reach the activity) and short
  enough to be muscle memory.
- **APP_SWITCH / VOICE_ASSIST / TV / TV_INPUT / colour buttons →
  open Moonode Launcher Settings.** Active only on non-Fire-TV devices.

When any settings-bound key is fired, the launcher calls
`pauseHomeNavigation(5 minutes)` and `moveTaskToBack(true)` so it doesn't
yank the operator back to the WebView while they're configuring Wi-Fi.

### 7. Reboot does **NOT** wipe WebView storage

It looks like it does, because after a reboot you may briefly see a
*new pairing digit* on `moonode.tv` before the page redirects to the
paired screen. This is a moonode.tv UX artifact, not a launcher problem.

For evidence the launcher's storage is intact, look in logcat for the
`MoonodePersist` tag (left in the build deliberately for diagnostics).
Cookies, Service Worker `CacheStorage`, `ScriptCache`, IndexedDB, and
`Local Storage/leveldb` all survive `adb reboot` byte-for-byte.

What actually happens on a Xiaomi reboot:

1. Wi-Fi association takes longer than the WebView startup.
2. `pages/generic` mounts, reads `localStorage["code"]` (the old pairing
   digit), renders the digit UI immediately.
3. `setDigits(<old code>)` either:
   - throws (offline) → catch block redirects via
     `localStorage["45%643D"]` → operator lands on the paired screen.
   - succeeds with `tvCode.active=false` (online but server has rotated
     the code) → page polls and keeps showing the digit indefinitely.
4. So in practice you almost always see the digit briefly, then the
   redirect kicks in.

This is by design. **Do not** add deep-link recovery in the launcher to
mask it — earlier attempts at that masked a real frontend-player bug
(only the first path segment was being saved, which broke the
`/business/<extId>` route entirely).

---

## Video signage on Xiaomi: audit & fitness

This section answers "is the Mi Box actually fit for video-driven signage,
or are we just hosting a web page on a slow box?". Audited against
`MiTV-AFMU0` (Amlogic S905X5M, Android 14, WebView Chromium 137).

### What the SoC can do

The Amlogic S905X5M is a media-centric SoC with a dedicated VPU. Hardware
decoders exposed via `c2.amlogic.*` (verified with `dumpsys media.player`):

| Codec | HW-accelerated decoder |
|-------|------------------------|
| H.264 / AVC | `c2.amlogic.avc.decoder` |
| H.265 / HEVC | `c2.amlogic.hevc.decoder` |
| VP9 | `c2.amlogic.vp9.decoder` |
| AV1 | `c2.amlogic.av1.decoder` |
| Dolby Vision | `c2.amlogic.dolby-vision.{dav1,dvav,dvhe}.decoder` |
| MPEG-2/4, VC-1, MJPEG | HW |
| VP8 | software (acceptable; rare in signage) |

Audio: AC-3, E-AC-3, AC-4, DTS / DTS-HD / DTS:X all hardware. AAC and MP3
are software (negligible CPU cost).

WebView Chromium 137 will route a `<video>` element through MediaCodec
automatically and pick the best HW decoder available — so any HEVC, VP9,
or AV1 ad we ship plays on the Amlogic VPU, not the CPU.

### What the launcher gives those decoders

All of the following are already configured for the WebView host. If you
add new TV models, keep this list in mind:

- `android:hardwareAccelerated="true"` on both the application and the
  activity (manifest). Without this, WebView falls back to software
  rasterisation and video decode bypasses the GPU.
- `android:largeHeap="true"`. The Mi Box has ~1.95 GB total / ~470 MB
  free; large heap raises our Dalvik cap so HEVC/AV1 reference frames
  don't trip the renderer's OOM killer.
- `WebViewController.setMediaPlaybackRequiresUserGesture(false)` (Dart).
  Signage must autoplay; without this, every `<video>.play()` on the
  page rejects with a `NotAllowedError`.
- `LauncherKeepAliveService` (foreground service). Keeps the launcher
  process at FOREGROUND_SERVICE priority so MIUI's lowmemorykiller
  doesn't reap the renderer mid-ad-rotation.
- `onTrimMemory ≥ RUNNING_MODERATE` triggers `System.gc()`. Buys a few
  seconds against LMK pressure during long video sessions on tight
  RAM devices.
- **`FLAG_KEEP_SCREEN_ON`** on the activity window (`MainActivity.onCreate`).
  This is the critical signage flag: the system display-off timer
  (Xiaomi defaults to 30 min, some Sony / TCL builds to 4 h) blanks the
  HDMI output even while the device itself is awake. Without this flag
  the signage looks broken at the customer site half an hour after
  install. The flag attaches to the *window* (not a CPU wakelock), so
  it is automatically released when the operator opens Settings — i.e.
  we don't fight the system's normal sleep policy when the user has
  intentionally backgrounded us.
- The frontend-player's `RotationSafeVideo` component composites video
  via a hidden `<video>` + WebGL canvas. The launcher does **not**
  promote video to a SurfaceView (no native MediaPlayer surfaces are
  attached), so CSS `transform: rotate()` from the player applies to
  video output the same way it applies to images. That's the trade-off
  we made on Fire OS and it carries over cleanly to Xiaomi.

### Performance ceiling on the Mi Box (observed)

Empirical, with a single 1080p H.264 ad in rotation alongside the static
signage UI:

- Memory: WebView + Flutter + foreground service settle around ~280 MB
  PSS. Budget ~470 MB free at boot, so we have ~190 MB of headroom for
  the GPU texture pool / decoder reference buffers.
- CPU: roughly 10–20 % on the four A55 cores during steady-state
  playback (decode is on the VPU, the CPU only services the WebGL
  uploader and JS event loop).
- Frame stability: `dumpsys gfxinfo com.moonode.launcher framestats`
  shows < 3 % janky frames on a fresh boot. Goes up to ~7 % after an
  hour of mixed image+video rotation as the canvas pipeline fragments
  the GPU heap; a daily reboot (cron via the operator's dashboard, not
  the launcher) keeps it pinned at < 5 %.

### Things this device cannot do

- **8K / HDR10+**: the panel and SoC do not output 8K, and HDR10+
  metadata is not honoured by the WebView compositor. Stick to 1080p
  HDR10 or SDR for ad creatives.
- **DRM-protected commercial content** in Moonode signage is not a
  goal here; the `*.secure` decoder variants exist on the device but
  the launcher does not request `MediaKeySystemConfiguration` with a
  hardware robustness level. If we ever ship DRM ads, that's a
  separate review.
- **Smooth 60 fps animated UI alongside HEVC decode**: the GPU is
  competent but the canvas-based video pipeline costs ~5 ms per frame.
  Keep dashboard animations minimal during the video carousel.

### Verdict

Yes — the Mi Box is a viable signage target for Moonode. Hardware decode
covers every modern codec, the WebView is recent enough to consume
them, and the launcher's existing memory / process / display-on
mitigations leave enough headroom for typical 1080p-mixed-media
deployments. Daily reboot recommended but not required.

If you ship a Mi Box that *isn't* the AFMU0 (e.g. older S905X4 boxes),
sanity-check `dumpsys media.player` for the same `c2.amlogic.{avc,hevc,vp9}`
HW decoders before committing to a deployment — older S905-family chips
sometimes drop VP9 hardware support.

### Audio-stripped video variants (the "freeze at 3 seconds" bug)

Even though signage `<video>` elements set `muted` in HTML, **Chromium
still decodes the audio track in the background**. Amlogic's software
AAC decoder occasionally chokes on a single bad packet a few seconds in
and Chromium fires `MEDIA_ERR_DECODE` (code 3); the picture freezes,
even though the H.264/HEVC frames are decoding fine on the VPU. We
reproduced this on overlay ads (3 s in, instead of the configured
30 s) and it would have hit any signage `<video>` long enough to
expose a defective audio packet.

The launcher itself can't fix this — the decoder is in WebView. The
fix lives across the stack:

1. **Backend**, on every video upload: generate a sibling `*.muted.mp4`
   file via `ffmpeg -an -c:v copy` (a 50–500 ms remux, no
   re-encode). Stored in the same Linode bucket as the original.
   See `backend/infrastructure/media/videoVariants.js`.
2. **Schema**: `MediaLibrary.mutedUrl` carries the variant URL;
   `BusinessScreen.overlayAds.media.mutedUrl` and
   `BusinessScreen.layout.cards[].staticContent.mutedImage` carry the
   embedded snapshot for the signage player. Both backends
   (main and `backend-socket`) declare these fields — Mongoose strict
   mode strips undeclared fields on the way out, so a missing
   declaration would silently break the feature.
3. **Player** (`frontend-player`): `OverlayAdvertising` and `VideoCard`
   prefer `mutedUrl`/`mutedImage` and fall back to `url`/`image` when
   absent. The `onError` gate (Path A) still keeps the overlay visible
   for the configured duration if a legacy asset trips the decoder.

**On the launcher side**: nothing to maintain. The launcher's WebView
will simply receive a different `<video src=…>` for new uploads and
play it without audio packets to choke on. Mobile uploads
(`backend-media`) are unaffected — they keep the original audio track
because the mobile app needs sound.

### Diagnostic removed (v1.0.20)

`MainActivity.logPersistenceFingerprint()` (a one-shot file walk +
`SharedPreferences` dump on every `onCreate`/`onResume`, used while
hunting the cache-persistence issue) has been removed. It ran on the
main thread and contributed measurable lag to remote-key responsiveness
on the Mi Box's quad-A55 SoC. If you ever need it again, restore from
git history — but prefer ADB:

```bash
adb shell run-as com.moonode.launcher \
    sh -c 'cat files/boot_counter; ls -la app_webview'
```

— same data, zero impact on the running launcher.

---

## Quick start

### 1. Enable ADB on the Mi box

`Settings → Device Preferences → About → Build` (click 7 times) →
back out → `Developer Options → USB debugging`.

The IP is in `Settings → Device Preferences → About → Status` (or use
hotspot share IP if your dev machine is the AP).

### 2. Connect

```bash
adb connect <MI_BOX_IP>:5555
```

If the device is `offline` after a reboot, kill and restart the ADB
server:

```bash
adb kill-server && adb start-server && adb connect <MI_BOX_IP>:5555
```

### 3. Build & deploy in soft mode

```bash
cd /Users/zeiv/Desktop/infrastructure/moonode-launcher
flutter build apk --release
./scripts/setup-moonode-launcher.sh <MI_BOX_IP>:5555
# (--soft is auto-forced on Xiaomi; you don't need to pass it)
```

When the script prompts you to, **press HOME on the Mi remote and pick
"Moonode Launcher"** in the system sheet. The script polls the Role
Manager and continues automatically.

### 4. Verify, then lock down

After a few minutes of confirming the screen is paired and content
plays:

```bash
./scripts/setup-moonode-launcher.sh --lockdown <MI_BOX_IP>:5555
```

`--lockdown` disables `com.mitv.tvhome.atv` and the Mi Box "Recents"
pop-up. The launcher then gets the HOME button by default with no
picker prompt.

### 5. Smoke-test reboot persistence

```bash
adb -s <MI_BOX_IP>:5555 reboot
# wait ~30 s for boot + Wi-Fi association
adb -s <MI_BOX_IP>:5555 logcat -d -s MoonodePersist | head -60
```

You should see:

```
Boot counter: previous=N current=N+1
SharedPrefs.cached_screen_id    = <screen-id>
SharedPrefs.cached_screen_id_at = <recent-timestamp>
[file] Cookies (24576 bytes)
[dir]  Service Worker/
  ...
```

If the `Cookies` line is missing or `app_webview/` is empty after a
reboot, *that* would be a real cache-wipe regression — file an issue
with the full `MoonodePersist` log block.

---

## Known limitations

### Wi-Fi status icon flickers in the moonode.tv footer on cold boot

Observed on Xiaomi after `adb reboot`: when the WebView loads, the
Wi-Fi indicator drawn by `moonode.tv`'s `SignageFooter` briefly
disappears or shows offline before settling on connected. This is a
symptom of MIUI's Wi-Fi association completing **after** the WebView
has already started rendering — so `connectivity_plus` (and the
in-page connectivity poll) reports offline for a second or two until
the network actually attaches.

It is harmless (the screen content still loads) and lives entirely on
the `moonode.tv` / `frontend-player` side, not in the launcher. The
launcher's own native Wi-Fi state is handled correctly; the Settings
screen and the 3× BACK escape both reach Wi-Fi config when needed.

Note: the system status bar (separate from the moonode.tv footer) is
intentionally hidden by `SystemUiMode.immersiveSticky` in `main.dart`
because that's what kiosk launchers do. That hide does **not** affect
the in-page footer indicator.

### Pairing digit flashes briefly on every cold boot

See **§7** above. It's a moonode.tv design choice (rotating pairing
codes for replay safety). The fix lives in
`frontend-player/src/pages/generic/index.js` (short-circuit on
`localStorage["45%643D"]` before showing digits) — out of scope for the
launcher.

### MIUI re-enables the stock launcher after OTAs

If a Mi Box gets an OTA in the field, `com.mitv.tvhome.atv` may come
back enabled. The Moonode `BootReceiver` retries still bring Moonode to
the foreground, but the Role Manager may need re-confirmation. Run
`setup-moonode-launcher.sh --lockdown` again on next maintenance visit.
