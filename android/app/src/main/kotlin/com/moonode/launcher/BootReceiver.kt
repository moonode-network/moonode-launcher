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
 *     ~6 seconds to win the race and end up on top. These extra launches are
 *     cheap no-ops on Android TV (we are already the foreground activity).
 */

package com.moonode.launcher

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

        // Fire TV retry schedule (ms after BOOT_COMPLETED). Spread across the
        // window during which the Amazon launcher is starting up.
        private val FIRE_TV_RETRY_DELAYS_MS = longArrayOf(800L, 2_500L, 5_000L, 8_000L)
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
            launchSelf(context)

            if (isFireTv()) {
                Log.d(TAG, "Fire TV detected - scheduling retry launches to override Amazon launcher")
                scheduleFireTvRetries(context)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error starting Moonode Launcher after boot: ", e)
        }
    }

    private fun launchSelf(context: Context) {
        try {
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
            }
            context.startActivity(launchIntent)
        } catch (e: Exception) {
            Log.e(TAG, "launchSelf failed", e)
        }
    }

    private fun scheduleFireTvRetries(context: Context) {
        val appContext = context.applicationContext
        val handler = Handler(Looper.getMainLooper())
        FIRE_TV_RETRY_DELAYS_MS.forEach { delay ->
            handler.postDelayed({
                Log.d(TAG, "Fire TV retry launch (delay=${delay}ms)")
                launchSelf(appContext)
            }, delay)
        }
    }

    private fun isFireTv(): Boolean {
        val manufacturer = (Build.MANUFACTURER ?: "").lowercase()
        val brand = (Build.BRAND ?: "").lowercase()
        val model = (Build.MODEL ?: "").lowercase()
        return manufacturer.contains("amazon") ||
            brand.contains("amazon") ||
            model.startsWith("aft") // AFTT, AFTSS, AFTKA, AFTKMST12, etc.
    }
}
