package com.example.third_eye

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * Broadcast receiver to restart the foreground service after device boot.
 * This ensures persistent operation even after the device is rebooted.
 */
class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "BootReceiver"
        private const val PREF_NAME = "third_eye_prefs"
        private const val KEY_SERVICE_ENABLED = "service_enabled"
        private const val KEY_SERVICE_PORT = "service_port"

        /**
         * Save service state to preferences so it can be restored after reboot.
         */
        fun saveServiceState(context: Context, enabled: Boolean, port: Int) {
            val prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            prefs.edit()
                .putBoolean(KEY_SERVICE_ENABLED, enabled)
                .putInt(KEY_SERVICE_PORT, port)
                .apply()
            Log.i(TAG, "Saved service state: enabled=$enabled, port=$port")
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return

        Log.i(TAG, "Boot completed, checking if service should restart")

        // Check shared preferences to see if service was running before reboot
        val prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        val serviceEnabled = prefs.getBoolean(KEY_SERVICE_ENABLED, false)
        val port = prefs.getInt(KEY_SERVICE_PORT, 5000)

        if (serviceEnabled) {
            Log.i(TAG, "Restarting foreground service on port $port")
            startForegroundService(context, port)
        } else {
            Log.i(TAG, "Service was not enabled before reboot, not starting")
        }
    }

    private fun startForegroundService(context: Context, port: Int) {
        val serviceIntent = Intent(context, UdpStreamService::class.java).apply {
            action = "START_STREAM"
            putExtra("port", port)
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
            Log.i(TAG, "Foreground service started successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start foreground service: ${e.message}")
        }
    }
}
