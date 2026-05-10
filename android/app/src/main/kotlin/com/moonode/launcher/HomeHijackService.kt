/*
 * Moonode Launcher
 * Copyright (C) 2026 Moonode
 *
 * HomeHijackService
 *
 * Fire OS aggressively protects its stock launcher activities
 * (com.amazon.tv.launcher / com.amazon.firehomestarter) so they cannot be
 * disabled via `pm disable-user`, and the standard Android HOME picker is
 * bypassed by Fire OS. The only reliable way to reclaim the HOME button on a
 * stock Fire TV is to detect when an Amazon launcher activity comes to the
 * foreground and immediately re-launch Moonode on top of it.
 *
 * This service is harmless on Android TV: it only triggers on a fixed allow-
 * list of Amazon package names that do not exist on AOSP/Google TV builds.
 *
 * The user must enable the service once in:
 *   Settings -> Accessibility -> Services -> Moonode HOME Guardian
 * (we deep-link them there from the in-app settings screen).
 */

package com.moonode.launcher

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.provider.Settings
import android.text.TextUtils
import android.util.Log
import android.view.accessibility.AccessibilityEvent

class HomeHijackService : AccessibilityService() {
    companion object {
        private const val TAG = "MoonodeHomeHijack"

        // Minimum time (ms) between two hijack relaunches so we never hot-loop
        // if the system briefly keeps an Amazon window in the foreground.
        private const val MIN_RELAUNCH_INTERVAL_MS = 600L

        /**
         * Packages whose foreground appearance should be intercepted and
         * replaced by Moonode. Add new Amazon HOME packages here if Fire OS
         * starts using a different one.
         */
        private val AMAZON_HOME_PACKAGES = setOf(
            "com.amazon.tv.launcher",
            "com.amazon.firehomestarter",
            "com.amazon.tv.firetvui",
            "com.amazon.firelauncher",
            "com.amazon.tv.leanbacklauncher"
        )

        private const val MOONODE_PACKAGE = "com.moonode.launcher"

        /**
         * Pause window. While `SystemClock.uptimeMillis() < pauseUntilMs` we
         * do NOT relaunch Moonode even if the Amazon home appears. This is
         * the escape hatch that lets the user reach Wi-Fi / Settings / any
         * native Fire OS screen without being yanked back to Moonode.
         *
         * Volatile so reads from the binder/UI thread see the latest write
         * from any other thread without a memory barrier dance.
         */
        @Volatile
        private var pauseUntilMs: Long = 0L

        /** Pause the hijack for the next [durationMs] milliseconds. */
        fun pauseFor(durationMs: Long) {
            pauseUntilMs = SystemClock.uptimeMillis() + durationMs
        }

        /** Resume immediately (cancel any active pause). */
        fun resume() {
            pauseUntilMs = 0L
        }

        /** True if the hijack is currently paused. */
        fun isPaused(): Boolean =
            SystemClock.uptimeMillis() < pauseUntilMs

        /** Milliseconds remaining in the active pause, or 0 if not paused. */
        fun pauseRemainingMs(): Long {
            val now = SystemClock.uptimeMillis()
            return if (pauseUntilMs > now) pauseUntilMs - now else 0L
        }

        /**
         * Returns true if THIS service is currently enabled in
         * Settings -> Accessibility. Used by the Dart UI to show an
         * "Enable HOME hijack" call-to-action when it is off.
         */
        fun isEnabled(context: Context): Boolean {
            return try {
                val expectedComponent = "${context.packageName}/${HomeHijackService::class.java.name}"
                val enabled = Settings.Secure.getInt(
                    context.contentResolver,
                    Settings.Secure.ACCESSIBILITY_ENABLED,
                    0
                ) == 1
                if (!enabled) return false
                val enabledServices = Settings.Secure.getString(
                    context.contentResolver,
                    Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
                ) ?: return false
                val splitter = TextUtils.SimpleStringSplitter(':')
                splitter.setString(enabledServices)
                splitter.any { it.equals(expectedComponent, ignoreCase = true) }
            } catch (e: Exception) {
                Log.w(TAG, "isEnabled check failed", e)
                false
            }
        }
    }

    @Volatile
    private var lastRelaunchAtMs: Long = 0L

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.d(TAG, "HomeHijackService connected")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return

        val pkg = event.packageName?.toString() ?: return
        if (pkg !in AMAZON_HOME_PACKAGES) return

        // Honor explicit pauses so the user can reach Settings / Wi-Fi / etc.
        // without us yanking them back to Moonode.
        if (isPaused()) {
            Log.i(TAG, "Amazon HOME detected ($pkg) but hijack is paused (${pauseRemainingMs()}ms left) - allowing")
            return
        }

        val now = SystemClock.uptimeMillis()
        if (now - lastRelaunchAtMs < MIN_RELAUNCH_INTERVAL_MS) return
        lastRelaunchAtMs = now

        Log.i(TAG, "Amazon HOME detected ($pkg) - relaunching Moonode")
        relaunchMoonode()
    }

    override fun onInterrupt() {
        // No-op
    }

    private fun relaunchMoonode() {
        try {
            val launchIntent = packageManager.getLaunchIntentForPackage(MOONODE_PACKAGE)
                ?: Intent().setClassName(MOONODE_PACKAGE, "$MOONODE_PACKAGE.MainActivity")

            launchIntent.apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
            startActivity(launchIntent)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to relaunch Moonode", e)
        }
    }
}
