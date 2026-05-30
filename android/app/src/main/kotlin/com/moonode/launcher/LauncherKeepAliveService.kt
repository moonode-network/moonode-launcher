/*
 * Moonode Launcher
 * Copyright (C) 2026 Moonode
 *
 * LauncherKeepAliveService
 *
 * Why: Xiaomi MiTV / MIUI aggressively kill backgrounded apps - even apps
 * that hold the HOME role - the moment they leave the foreground (operator
 * opens Settings, etc). When the operator comes back, the launcher process
 * has been wiped, the WebView is fresh, and the SW Cache API has to rehydrate
 * from disk. The visible result is a "loading" splash on every return.
 *
 * What it does: a minimal foreground service that promotes the launcher
 * process to FOREGROUND_SERVICE priority. Android's lowmemorykiller and
 * MIUI's task killer both consider apps with a foreground service "in use"
 * and stop reaping them. The notification is low-priority and silent so it
 * doesn't disturb the operator (and on Android TV / Google TV the notification
 * is invisible to TV users anyway since the system tray isn't surfaced on the
 * TV home screen).
 *
 * On non-Xiaomi devices this is a tiny memory cost (~few MB for the service
 * binder) but no user-visible impact, so we run it everywhere for consistency.
 */

package com.moonode.launcher

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

class LauncherKeepAliveService : Service() {
    companion object {
        private const val TAG = "MoonodeKeepAlive"
        private const val CHANNEL_ID = "moonode_launcher_keepalive"
        private const val CHANNEL_NAME = "Moonode Launcher"
        private const val NOTIFICATION_ID = 1001

        fun start(context: Context) {
            val intent = Intent(context, LauncherKeepAliveService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                Log.w(TAG, "Could not start keep-alive service: ${e.message}")
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        try {
            createChannel()
            startForeground(NOTIFICATION_ID, buildNotification())
            Log.i(TAG, "Keep-alive service started")
        } catch (e: Exception) {
            // If foregrounding fails (missing permission, OEM restriction,
            // notification policy, etc.) swallow the error and stop the
            // service. The launcher MUST NOT crash in this path - falling
            // back to plain process priority is acceptable; we only lose
            // the protection against MIUI's task killer.
            Log.e(TAG, "Foreground promotion failed - stopping service: ${e.message}", e)
            try { stopSelf() } catch (_: Exception) { }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // START_STICKY: if the system kills us anyway, restart immediately.
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Operator swiped Moonode away from the recents tray (rare on TV but
        // happens on Xiaomi via the Mi Box pop-up). Re-arm ourselves so the
        // process priority stays elevated until the next reboot.
        super.onTaskRemoved(rootIntent)
        try {
            val restartIntent = Intent(applicationContext, LauncherKeepAliveService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                applicationContext.startForegroundService(restartIntent)
            } else {
                applicationContext.startService(restartIntent)
            }
        } catch (_: Exception) { }
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_MIN
            ).apply {
                description = "Keeps the Moonode display running"
                setShowBadge(false)
                enableLights(false)
                enableVibration(false)
                setSound(null, null)
                lockscreenVisibility = Notification.VISIBILITY_SECRET
            }
            mgr.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Moonode Launcher")
            .setContentText("Display active")
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setOngoing(true)
            .setSilent(true)
            .setShowWhen(false)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.foregroundServiceBehavior = Notification.FOREGROUND_SERVICE_IMMEDIATE
        }
        return builder.build()
    }
}
