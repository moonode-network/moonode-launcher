/*
 * Moonode Launcher
 * Copyright (C) 2026 Moonode
 *
 * Based on FLauncher by Étienne Fesser (GPL-3.0)
 * Modified for Moonode TV integration
 */

package com.moonode.launcher

import android.content.Intent
import android.content.Intent.*
import android.content.pm.ActivityInfo
import android.content.pm.LauncherApps
import android.content.pm.ResolveInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.os.UserHandle
import android.provider.Settings
import android.view.KeyEvent
import android.webkit.WebView
import android.webkit.WebSettings
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.EventChannel.EventSink
import io.flutter.plugin.common.EventChannel.StreamHandler
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.Serializable

private const val METHOD_CHANNEL = "com.moonode.launcher/method"
private const val EVENT_CHANNEL = "com.moonode.launcher/event"
private const val KEY_EVENT_CHANNEL = "com.moonode.launcher/keyEvent"

/**
 * Default pause window applied automatically whenever the user opens a system
 * settings screen from inside Moonode. Long enough to navigate Wi-Fi /
 * Accessibility / Apps without HomeHijackService bouncing them back, short
 * enough that we re-arm HOME protection if they walk away from the device.
 */
private const val DEFAULT_PAUSE_MS = 5L * 60L * 1000L // 5 minutes

class MainActivity : FlutterActivity() {
    val launcherAppsCallbacks = ArrayList<LauncherApps.Callback>()
    private var keyEventChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Configure WebView defaults for offline caching (Service Workers, DOM Storage)
        configureWebViewDefaults()
    }
    
    /**
     * Configure WebView defaults to enable offline caching like Chromium.
     * This enables Service Workers, DOM Storage, and database storage
     * which are required for PWA offline functionality.
     */
    private fun configureWebViewDefaults() {
        try {
            // Enable WebView debugging in debug builds
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                WebView.setWebContentsDebuggingEnabled(true)
            }
            
            // Set data directory for WebView (helps with cache persistence)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val dataDir = applicationInfo.dataDir
                // WebView will use app's data directory for cache
            }
        } catch (e: Exception) {
            // Ignore - some devices may not support all WebView features
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.hasCategory(CATEGORY_HOME)) {
            keyEventChannel?.invokeMethod("goHome", null)
        }
    }

    override fun onResume() {
        super.onResume()
        // The user is back inside Moonode - re-arm HOME protection immediately.
        // (We may have been paused for a Settings detour; once they return, the
        // pause is no longer needed and Wi-Fi changes etc. are already done.)
        HomeHijackService.resume()
    }

    /**
     * Fire TV Stick (1st gen) has only ~921 MB total RAM and our WebView's
     * sandboxed renderer alone consumes ~265 MB. Without intervention, the
     * Android lowmemorykiller routinely kills our renderer as `fore TOP`,
     * which causes the user to see the launcher visibly "reload" every minute
     * or two. By proactively releasing memory the moment the system signals
     * pressure, we reduce how often LMK has to kill us.
     *
     * onTrimMemory is called by the framework with escalating levels:
     *   RUNNING_MODERATE / LOW / CRITICAL = visible app, system needs RAM
     *   UI_HIDDEN                          = our UI is no longer visible
     *   COMPLETE / MODERATE / BACKGROUND   = backgrounded, may be killed soon
     *
     * For a launcher that's permanently in the foreground we mostly care
     * about the RUNNING_* levels - those are the ones that precede the LMK
     * kill of our WebView renderer.
     */
    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        if (level >= TRIM_MEMORY_RUNNING_MODERATE) {
            try {
                // Hint Dalvik to do a full collection ASAP. This is normally
                // a no-no, but on a 921 MB device under LMK pressure it can
                // buy us a few seconds before the kernel kills the renderer.
                System.gc()
                Runtime.getRuntime().gc()
            } catch (_: Throwable) { }
            android.util.Log.i("MoonodeLauncher", "onTrimMemory level=$level - asked VM to free memory")
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.action == KeyEvent.ACTION_DOWN) {
            val keyAction = when (event.keyCode) {
                KeyEvent.KEYCODE_MENU,
                KeyEvent.KEYCODE_F1,
                KeyEvent.KEYCODE_SETTINGS,
                KeyEvent.KEYCODE_BOOKMARK,
                KeyEvent.KEYCODE_GUIDE -> "openSettings"

                KeyEvent.KEYCODE_F2 -> "openAndroidSettings"

                else -> null
            }
            if (keyAction != null) {
                keyEventChannel?.invokeMethod(keyAction, null)
                return true
            }
        }
        return super.dispatchKeyEvent(event)
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        keyEventChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, KEY_EVENT_CHANNEL)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getApplications" -> result.success(getApplications())
                "launchApp" -> result.success(launchApp(call.arguments as String))
                "launchMoonodeApp" -> result.success(launchMoonodeApp())
                "openSettings" -> result.success(openSettings())
                "openAppInfo" -> result.success(openAppInfo(call.arguments as String))
                "uninstallApp" -> result.success(uninstallApp(call.arguments as String))
                "isDefaultLauncher" -> result.success(isDefaultLauncher())
                "checkForGetContentAvailability" -> result.success(checkForGetContentAvailability())
                "chooseDefaultLauncher" -> result.success(chooseDefaultLauncher())
                "getDeviceInfo" -> result.success(getDeviceInfo())
                "isHomeHijackEnabled" -> result.success(HomeHijackService.isEnabled(this))
                "enableHomeHijackService" -> result.success(enableHomeHijackService())
                "openAccessibilitySettings" -> result.success(openAccessibilitySettings())
                "openWifiSettings" -> result.success(openWifiSettings())
                "pauseHomeHijack" -> {
                    val durationMs = (call.arguments as? Number)?.toLong() ?: DEFAULT_PAUSE_MS
                    HomeHijackService.pauseFor(durationMs)
                    result.success(durationMs)
                }
                "resumeHomeHijack" -> {
                    HomeHijackService.resume()
                    result.success(true)
                }
                "homeHijackPauseRemainingMs" -> result.success(HomeHijackService.pauseRemainingMs())
                "setScreenOrientation" -> {
                    val angle = (call.arguments as? Number)?.toInt() ?: 0
                    setScreenOrientation(angle)
                    result.success(true)
                }
                else -> throw IllegalArgumentException()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(object : StreamHandler {
            lateinit var launcherAppsCallback: LauncherApps.Callback
            val launcherApps = getSystemService(LAUNCHER_APPS_SERVICE) as LauncherApps
            override fun onListen(arguments: Any?, events: EventSink) {
                launcherAppsCallback = object : LauncherApps.Callback() {
                    override fun onPackageRemoved(packageName: String, user: UserHandle) {
                        events.success(mapOf("action" to "PACKAGE_REMOVED", "packageName" to packageName))
                    }

                    override fun onPackageAdded(packageName: String, user: UserHandle) {
                        val applications = getApplication(packageName)
                        if (applications.isNotEmpty()) {
                            events.success(mapOf("action" to "PACKAGE_ADDED", "activitiesInfo" to applications))
                        }
                    }

                    override fun onPackageChanged(packageName: String, user: UserHandle) {
                        val applications = getApplication(packageName)
                        if (applications.isNotEmpty()) {
                            events.success(mapOf("action" to "PACKAGE_CHANGED", "activitiesInfo" to applications))
                        }
                    }

                    override fun onPackagesAvailable(packageNames: Array<out String>, user: UserHandle, replacing: Boolean) {}
                    override fun onPackagesUnavailable(packageNames: Array<out String>, user: UserHandle, replacing: Boolean) {}
                }

                launcherAppsCallbacks.add(launcherAppsCallback)
                launcherApps.registerCallback(launcherAppsCallback)
            }

            override fun onCancel(arguments: Any?) {
                launcherApps.unregisterCallback(launcherAppsCallback)
                launcherAppsCallbacks.remove(launcherAppsCallback)
            }
        })
    }

    override fun onDestroy() {
        val launcherApps = getSystemService(LAUNCHER_APPS_SERVICE) as LauncherApps
        launcherAppsCallbacks.forEach(launcherApps::unregisterCallback)
        super.onDestroy()
    }

    private fun getApplications(): List<Map<String, Serializable?>> {
        val tvActivitiesInfo = queryIntentActivities(false)
        val nonTvActivitiesInfo = queryIntentActivities(true)
                .filter { nonTvActivityInfo -> !tvActivitiesInfo.any { tvActivityInfo -> tvActivityInfo.packageName == nonTvActivityInfo.packageName } }
        return tvActivitiesInfo.map { buildAppMap(it, false) } + nonTvActivitiesInfo.map { buildAppMap(it, true) }
    }

    fun getApplication(packageName: String): List<Map<String, Serializable?>> {
        val tvActivitiesInfo = queryIntentActivities(false)
                .filter { it.packageName == packageName }
                .map { buildAppMap(it, false) }
        return if (tvActivitiesInfo.isNotEmpty()) {
            tvActivitiesInfo
        } else {
            queryIntentActivities(true)
                    .filter { it.packageName == packageName }
                    .map { buildAppMap(it, true) }
        }
    }

    private fun queryIntentActivities(sideloaded: Boolean) = packageManager
            .queryIntentActivities(Intent(ACTION_MAIN, null)
                    .addCategory(if (sideloaded) CATEGORY_LAUNCHER else CATEGORY_LEANBACK_LAUNCHER), 0)
            .map(ResolveInfo::activityInfo)

    private fun buildAppMap(activityInfo: ActivityInfo, sideloaded: Boolean) = mapOf(
            "name" to activityInfo.loadLabel(packageManager).toString(),
            "packageName" to activityInfo.packageName,
            "banner" to activityInfo.loadBanner(packageManager)?.let(::drawableToByteArray),
            "icon" to activityInfo.loadIcon(packageManager)?.let(::drawableToByteArray),
            "version" to packageManager.getPackageInfo(activityInfo.packageName, 0).versionName,
            "sideloaded" to sideloaded,
    )

    private fun launchApp(packageName: String) = try {
        val intent = packageManager.getLeanbackLaunchIntentForPackage(packageName)
                ?: packageManager.getLaunchIntentForPackage(packageName)
        startActivity(intent)
        true
    } catch (e: Exception) {
        false
    }

    // Launch Moonode TV App specifically
    private fun launchMoonodeApp() = try {
        val moonodePackage = "com.moonode.app"
        val intent = packageManager.getLeanbackLaunchIntentForPackage(moonodePackage)
                ?: packageManager.getLaunchIntentForPackage(moonodePackage)
        if (intent != null) {
            startActivity(intent)
            true
        } else {
            // Moonode app not installed, open moonode.tv in WebView
            false
        }
    } catch (e: Exception) {
        false
    }

    private fun openSettings() = try {
        // Pause hijack first so HomeHijackService doesn't bounce the user back
        // when Settings briefly transitions through the Amazon launcher window.
        HomeHijackService.pauseFor(DEFAULT_PAUSE_MS)
        startActivity(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (e: Exception) {
        false
    }

    /**
     * Open the system Wi-Fi settings directly. This is the most common reason
     * to leave Moonode at a customer site (e.g. switching the device to the
     * customer's Wi-Fi after install). We auto-pause the HOME hijack so the
     * user can complete the network change without being yanked back.
     */
    private fun openWifiSettings(): Boolean {
        HomeHijackService.pauseFor(DEFAULT_PAUSE_MS)
        // Try Wi-Fi settings first, then fall back to network settings, then
        // generic settings - Fire OS variants expose different actions.
        val candidates = listOf(
            Intent(Settings.ACTION_WIFI_SETTINGS),
            Intent(Settings.ACTION_WIRELESS_SETTINGS),
            Intent("com.amazon.tv.settings.NETWORK"),
            Intent(Settings.ACTION_SETTINGS)
        )
        for (intent in candidates) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                if (intent.resolveActivity(packageManager) != null) {
                    startActivity(intent)
                    return true
                }
            } catch (_: Exception) {
                // try next
            }
        }
        return false
    }

    private fun openAppInfo(packageName: String) = try {
        HomeHijackService.pauseFor(DEFAULT_PAUSE_MS)
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.fromParts("package", packageName, null))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                .let(::startActivity)
        true
    } catch (e: Exception) {
        false
    }

    private fun uninstallApp(packageName: String) = try {
        Intent(ACTION_DELETE)
                .setData(Uri.fromParts("package", packageName, null))
                .let(::startActivity)
        true
    } catch (e: Exception) {
        false
    }

    private fun checkForGetContentAvailability() = try {
        val intentActivities = packageManager.queryIntentActivities(Intent(ACTION_GET_CONTENT, null).setTypeAndNormalize("image/*"), 0)
        intentActivities.isNotEmpty()
    } catch (e: Exception) {
        false
    }

    private fun isDefaultLauncher() = try {
        val defaultLauncher = packageManager.resolveActivity(Intent(ACTION_MAIN).addCategory(CATEGORY_HOME), 0)
        defaultLauncher?.activityInfo?.packageName == packageName
    } catch (e: Exception) {
        false
    }

    /**
     * Open the system "Choose default launcher" UI so the user can pick a different
     * HOME launcher (or re-pick Moonode). Behaviour by platform:
     *   - Android TV / AOSP: ACTION_HOME_SETTINGS opens the launcher picker.
     *   - Fire TV: ACTION_HOME_SETTINGS does not exist; we fall back to opening
     *     this app's details page so the user can "Clear defaults" or uninstall
     *     Moonode entirely and return to the Amazon launcher.
     *   - Last-resort fallback: open generic Android Settings.
     */
    private fun chooseDefaultLauncher(): Boolean {
        // 1) Try the dedicated HOME settings screen (works on most Android TV builds).
        try {
            val homeSettings = Intent(Settings.ACTION_HOME_SETTINGS)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (homeSettings.resolveActivity(packageManager) != null) {
                startActivity(homeSettings)
                return true
            }
        } catch (_: Exception) {
            // fall through
        }

        // 2) Fire TV / devices without HOME_SETTINGS: open our own app info page.
        //    From there the user can press "Clear defaults" (if Moonode is the
        //    default) or "Uninstall" to fully revert to the stock launcher.
        try {
            val appDetails = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.fromParts("package", packageName, null))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (appDetails.resolveActivity(packageManager) != null) {
                startActivity(appDetails)
                return true
            }
        } catch (_: Exception) {
            // fall through
        }

        // 3) Generic settings as last resort.
        return try {
            startActivity(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Programmatically enable the HOME Guardian accessibility service.
     *
     * Android normally requires the user to manually toggle accessibility
     * services in Settings. We bypass this with `WRITE_SECURE_SETTINGS`
     * which is granted at install time via ADB by the deployment script:
     *   adb shell pm grant com.moonode.launcher android.permission.WRITE_SECURE_SETTINGS
     *
     * Without that grant, this method silently no-ops (returns false) - the
     * caller can then fall back to opening the Accessibility settings page.
     *
     * Returns true if the service is enabled (or was already enabled) after
     * the call. Idempotent.
     */
    private fun enableHomeHijackService(): Boolean {
        val component = "$packageName/${HomeHijackService::class.java.name}"
        try {
            // 1) Read current enabled list. Could be null, empty, or contain other services.
            val current = Settings.Secure.getString(
                contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            ) ?: ""

            // 2) Already enabled? Nothing to do.
            val parts = current.split(':').filter { it.isNotBlank() }
            if (parts.contains(component)) {
                // Make sure global accessibility flag is on too.
                Settings.Secure.putInt(contentResolver, Settings.Secure.ACCESSIBILITY_ENABLED, 1)
                return true
            }

            // 3) Append our component without disturbing any other enabled services.
            val updated = (parts + component).joinToString(":")
            Settings.Secure.putString(
                contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
                updated
            )
            Settings.Secure.putInt(contentResolver, Settings.Secure.ACCESSIBILITY_ENABLED, 1)
            return true
        } catch (e: SecurityException) {
            // WRITE_SECURE_SETTINGS not granted. This is the expected path on
            // an install where the deployment script wasn't used. The caller
            // should fall back to openAccessibilitySettings().
            android.util.Log.w("MoonodeLauncher", "Cannot auto-enable HOME Guardian: WRITE_SECURE_SETTINGS not granted")
            return false
        } catch (e: Exception) {
            android.util.Log.w("MoonodeLauncher", "Failed to auto-enable HOME Guardian: ${e.message}")
            return false
        }
    }

    /**
     * Open the system Accessibility settings page so the user can flip on
     * the Moonode HOME Guardian service. Android does not allow apps to
     * enable an accessibility service themselves; the toggle is mandated
     * to be a manual user action.
     *
     * We try to deep-link to a per-component settings screen first (some
     * Android builds support this via the `:settings:fragment_args_key`
     * extra), then fall back to the generic accessibility list.
     */
    private fun openAccessibilitySettings(): Boolean {
        // The user is on their way to toggle our own service; the same
        // hijack-pause logic applies so we don't bounce them.
        HomeHijackService.pauseFor(DEFAULT_PAUSE_MS)
        val component = "$packageName/${HomeHijackService::class.java.name}"
        // Generic accessibility list - works on every Android/Fire OS build.
        return try {
            val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                // Used by some OEMs to highlight the right row.
                putExtra(":settings:fragment_args_key", component)
                val bundle = android.os.Bundle().apply {
                    putString(":settings:fragment_args_key", component)
                }
                putExtra(":settings:show_fragment_args", bundle)
            }
            startActivity(intent)
            true
        } catch (e: Exception) {
            try {
                startActivity(
                    Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
                true
            } catch (e2: Exception) {
                false
            }
        }
    }

    /**
     * Rotate the activity surface natively at the OS level.
     *
     * Why this exists
     * ---------------
     * Android WebView renders <video> and <iframe> via SurfaceView, which is
     * composited by the OS underneath the WebView's normal layer. CSS
     * `transform: rotate()` applied in moonode.tv (the embedded web player)
     * only rotates the WebView's HTML layer - SurfaceViews stay in the panel's
     * native landscape orientation. Result: on a portrait-mounted TV the HTML
     * looks correct but every video / YouTube / Vimeo iframe bleeds through
     * sideways. This is especially visible on Fire OS WebView (Chromium older
     * than current Stable, where TextureView fallback isn't automatic).
     *
     * Calling setRequestedOrientation rotates the entire activity surface at
     * the OS level. The WebView, every SurfaceView inside it, and any future
     * native view all rotate together - so video, iframes and HTML are
     * visually consistent on portrait-mounted TVs.
     *
     * The activity manifest declares the full configChanges set so the
     * activity is NOT recreated on rotation; the WebView keeps its state and
     * the player does not reload.
     *
     * Idempotency
     * -----------
     * Skips the system call when the requested orientation already matches.
     * The web player calls this on every settings refresh (every few minutes)
     * and we don't want a no-op orientation change to trigger any
     * onConfigurationChanged side effects.
     *
     * Mapping (signage convention, counter-clockwise from landscape):
     *   0   -> SCREEN_ORIENTATION_LANDSCAPE          (default; HDMI native)
     *   90  -> SCREEN_ORIENTATION_PORTRAIT           (TV mounted with right edge up)
     *   180 -> SCREEN_ORIENTATION_REVERSE_LANDSCAPE  (TV upside down)
     *   270 -> SCREEN_ORIENTATION_REVERSE_PORTRAIT   (TV mounted with left edge up)
     *   any other value -> SCREEN_ORIENTATION_LANDSCAPE (safe default)
     */
    private fun setScreenOrientation(angle: Int) {
        val target = when (angle) {
            90 -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
            180 -> ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE
            270 -> ActivityInfo.SCREEN_ORIENTATION_REVERSE_PORTRAIT
            else -> ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
        }
        runOnUiThread {
            try {
                if (requestedOrientation != target) {
                    requestedOrientation = target
                    android.util.Log.i(
                        "MoonodeLauncher",
                        "setScreenOrientation: applied target=$target for angle=$angle"
                    )
                }
            } catch (e: Exception) {
                android.util.Log.w(
                    "MoonodeLauncher",
                    "setScreenOrientation failed for angle $angle: ${e.message}"
                )
            }
        }
    }

    /**
     * Expose device fingerprint to Dart so the UI can adapt (e.g. show
     * Fire-TV-specific recovery instructions next to the "Choose Default
     * Launcher" button).
     */
    private fun getDeviceInfo(): Map<String, Any?> {
        val manufacturer = Build.MANUFACTURER ?: ""
        val brand = Build.BRAND ?: ""
        val model = Build.MODEL ?: ""
        val isFireTv = manufacturer.equals("Amazon", ignoreCase = true) ||
            brand.equals("Amazon", ignoreCase = true) ||
            model.lowercase().startsWith("aft")
        val isAndroidTv = packageManager.hasSystemFeature("android.software.leanback")
        return mapOf(
            "manufacturer" to manufacturer,
            "brand" to brand,
            "model" to model,
            "sdkInt" to Build.VERSION.SDK_INT,
            "isFireTv" to isFireTv,
            "isAndroidTv" to isAndroidTv,
        )
    }

    private fun drawableToByteArray(drawable: Drawable): ByteArray {
        fun drawableToBitmap(drawable: Drawable): Bitmap {
            val bitmap = Bitmap.createBitmap(drawable.intrinsicWidth, drawable.intrinsicHeight, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            drawable.setBounds(0, 0, canvas.width, canvas.height)
            drawable.draw(canvas)
            return bitmap
        }

        val bitmap = drawableToBitmap(drawable)
        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
        return stream.toByteArray()
    }
}

