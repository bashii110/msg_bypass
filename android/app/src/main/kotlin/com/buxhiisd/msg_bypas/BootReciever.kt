package com.buxhiisd.msg_bypas

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * FIXED: Now reads from correct SharedPreferences location
 * Restarts the background monitoring service after device reboot
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context?, intent: Intent?) {
        context ?: return

        Log.d("BootReceiver", "📱 Boot completed, action: ${intent?.action}")

        when (intent?.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON" -> {

                // FIXED: Check BOTH SharedPreferences locations
                // Flutter stores in "FlutterSharedPreferences"
                val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val flutterMonitoring = flutterPrefs.getBoolean("flutter.monitoring_enabled", false)

                // Native stores in "app_prefs"
                val nativePrefs = context.getSharedPreferences("app_prefs", Context.MODE_PRIVATE)
                val nativeMonitoring = nativePrefs.getBoolean("monitoring_enabled", false)

                val wasMonitoring = flutterMonitoring || nativeMonitoring

                Log.d("BootReceiver", "Flutter monitoring: $flutterMonitoring")
                Log.d("BootReceiver", "Native monitoring: $nativeMonitoring")
                Log.d("BootReceiver", "Final decision: $wasMonitoring")

                if (wasMonitoring) {
                    Log.d("BootReceiver", "✅ Monitoring was enabled - restarting service")

                    val serviceIntent = Intent(context, AccidentMonitoringService::class.java)

                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            context.startForegroundService(serviceIntent)
                        } else {
                            context.startService(serviceIntent)
                        }

                        Log.d("BootReceiver", "✅ Service restarted successfully after boot")
                    } catch (e: Exception) {
                        Log.e("BootReceiver", "❌ Failed to restart service: ${e.message}")
                    }
                } else {
                    Log.d("BootReceiver", "⏸️ Monitoring was disabled - not starting service")
                }
            }
        }
    }
}