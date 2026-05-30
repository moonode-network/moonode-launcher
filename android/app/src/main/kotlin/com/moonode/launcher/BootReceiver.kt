/*
 * Moonode Launcher
 * Copyright (C) 2026 Moonode
 *
 * BootReceiver - Starts the launcher automatically on device boot.
 *
 * Behaviour:
 *   - Android TV / AOSP TV boxes: a single launch is enough because Moonode
 *     can be set as the default HOME activity and the system will route the
 *     post-boot HOME intent to us anyway.
 *   - Amazon Fire TV: the Amazon launcher (com.amazon.tv.launcher) cannot be
 *     replaced via the standard HOME picker, so it will come to the foreground
 *     after BOOT_COMPLETED. We re-launch ourselves a few times in the first
 *     ~8 seconds to win the race and end up on top.
 *   - Xiaomi MiTV / Mi Box: MIUI may re-enable the priv-app Google launcher
 *     on reboot. A short retry window (only while we are NOT yet foreground)
 *     helps us win the boot race without hammering the activity once we are
 *     already on screen — repeated startActivity calls were causing visible
 *     WebView reloads ("launcher keeps firing back").
 */

package com.moonode.launcher

import android.app.ActivityManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log

class BootReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "MoonodeBootReceiver"

        private val handler = Handler(Looper.getMainLooper())
        private val pendingRetries = mutableListOf<Runnable>()

        // Fire TV retry schedule (ms after BOOT_COMPLETED).
        private val FIRE_TV_RETRY_DELAYS_MS = longArrayOf(800L, 2_500L, 5_000L, 8_000L)

        // Xiaomi: fewer retries, only fire when not yet foreground.
        private val XIAOMI_RETRY_DELAYS_MS = longArrayOf(2_000L, 5_000L, 8_000L)

        /** Cancel any boot-race retries (e.g. user opened Settings). */
        fun cancelPendingRetries() {
            synchronized(pendingRetries) {
                pendingRetries.forEach { handler.removeCallbacks(it) }
                pendingRetries.clear()
            }
            Log.d(TAG, "Boot retry schedule cancelled")
        }

        private fun isMoonodeInForeground(context: Context): Boolean {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val processes = am.runningAppProcesses ?: return false
            return processes.any {
                it.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND &&
                    it.processName == context.packageName
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent?) {
        try {
            val action = intent?.action ?: return
            if (action != Intent.ACTION_BOOT_COMPLETED &&
                action != Intent.ACTION_LOCKED_BOOT_COMPLETED &&
                action != "android.intent.action.QUICKBOOT_POWERON"
            ) {
                return
            }

            Log.d(TAG, "Boot completed ($action), launching Moonode Launcher")

            // Start the keep-alive service immediately on boot so the
            // process is protected from MIUI's task killer even before
            // the activity has a chance to start it.
            try {
                LauncherKeepAliveService.start(context.applicationContext)
            } catch (e: Exception) {
                Log.w(TAG, "Could not start keep-alive on boot: ${e.message}")
            }

            launchSelfIfNeeded(context)

            if (isFireTv()) {
                Log.d(TAG, "Fire TV detected - scheduling retry launches to override Amazon launcher")
                scheduleRetries(context, FIRE_TV_RETRY_DELAYS_MS, "Fire TV")
            } else if (isXiaomi()) {
                Log.d(TAG, "Xiaomi detected - scheduling conditional retry launches")
                scheduleRetries(context, XIAOMI_RETRY_DELAYS_MS, "Xiaomi")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error starting Moonode Launcher after boot: ", e)
        }
    }

    private fun launchSelfIfNeeded(context: Context) {
        if (isMoonodeInForeground(context)) {
            Log.d(TAG, "Moonode already foreground - skipping launch")
            cancelPendingRetries()
            return
        }
        launchSelf(context)
    }

    private fun launchSelf(context: Context) {
        try {
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                // Do NOT use CLEAR_TOP here — on Xiaomi it was recycling the
                // WebView task and making cached content look like it vanished.
            }
            context.startActivity(launchIntent)
        } catch (e: Exception) {
            Log.e(TAG, "launchSelf failed", e)
        }
    }

    private fun scheduleRetries(context: Context, delaysMs: LongArray, label: String) {
        cancelPendingRetries()
        val appContext = context.applicationContext
        delaysMs.forEach { delay ->
            val runnable = Runnable {
                if (MainActivity.isHomeNavigationPaused()) {
                    Log.d(TAG, "$label retry skipped - user in Settings detour")
                    cancelPendingRetries()
                    return@Runnable
                }
                if (isMoonodeInForeground(appContext)) {
                    Log.d(TAG, "$label retry skipped - already foreground")
                    cancelPendingRetries()
                    return@Runnable
                }
                Log.d(TAG, "$label retry launch (delay=${delay}ms)")
                launchSelf(appContext)
            }
            synchronized(pendingRetries) {
                pendingRetries.add(runnable)
            }
            handler.postDelayed(runnable, delay)
        }
    }

    private fun isXiaomi(): Boolean {
        val manufacturer = (Build.MANUFACTURER ?: "").lowercase()
        val brand = (Build.BRAND ?: "").lowercase()
        val model = (Build.MODEL ?: "").lowercase()
        return manufacturer.contains("xiaomi") ||
            brand.contains("xiaomi") ||
            brand.contains("redmi") ||
            model.contains("mitv") ||
            model.contains("mibox")
    }

    private fun isFireTv(): Boolean {
        val manufacturer = (Build.MANUFACTURER ?: "").lowercase()
        val brand = (Build.BRAND ?: "").lowercase()
        val model = (Build.MODEL ?: "").lowercase()
        return manufacturer.contains("amazon") ||
            brand.contains("amazon") ||
            model.startsWith("aft")
    }
}
