package com.buxhiisd.msg_bypas

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == "android.intent.action.QUICKBOOT_POWERON") {

            Log.d("BootReceiver", "📱 Device booted - checking if monitoring was enabled")

            // Check if monitoring was previously enabled
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val wasMonitoring = prefs.getBoolean("flutter.monitoring_enabled", false)

            if (wasMonitoring) {
                Log.d("BootReceiver", "✅ Monitoring was enabled - restarting service")

                val serviceIntent = Intent(context, AccidentMonitoringService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(serviceIntent)
                } else {
                    context.startService(serviceIntent)
                }
            } else {
                Log.d("BootReceiver", "⏸️ Monitoring was disabled - not starting service")
            }
        }
    }
}