/*
 * Moonode Launcher
 * Copyright (C) 2025 Moonode
 *
 * BootReceiver - Starts the launcher automatically on device boot
 * Based on Moonode Android-TV BootReceiver pattern
 */

package com.moonode.launcher

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class BootReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "MoonodeBootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        try {
            if (intent != null && 
                (Intent.ACTION_BOOT_COMPLETED == intent.action || 
                 Intent.ACTION_LOCKED_BOOT_COMPLETED == intent.action)) {
                
                Log.d(TAG, "Boot completed, launching Moonode Launcher")
                
                // Create an intent to launch MainActivity
                val launchIntent = Intent(context, MainActivity::class.java).apply {
                    // FLAG_ACTIVITY_NEW_TASK is required when launching from non-Activity context
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                }
                
                // Start the MainActivity
                context.startActivity(launchIntent)
                Log.d(TAG, "Moonode Launcher started successfully")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error starting Moonode Launcher after boot: ", e)
        }
    }
}

