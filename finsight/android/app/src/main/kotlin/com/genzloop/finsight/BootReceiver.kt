package com.genzloop.finsight

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Restarts the background service after device reboot.
 */
 
class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "BootReceiver"
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        if (intent?.action == Intent.ACTION_BOOT_COMPLETED) {
            Log.d(TAG, "Device booted — FinSight background service will restart via flutter_background_service autoStart")
            // The flutter_background_service plugin handles auto-start.
            // This receiver simply ensures we're registered for BOOT_COMPLETED.
        }
    }
}
