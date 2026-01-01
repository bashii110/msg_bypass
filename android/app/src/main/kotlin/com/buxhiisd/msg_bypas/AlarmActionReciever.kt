package com.buxhiisd.msg_bypas

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class AlarmActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == "ACTION_USER_SAFE") {
            val stopIntent = Intent(context, AlarmForegroundService::class.java)
            stopIntent.action = "STOP_ALARM"
            context.startService(stopIntent)
        }
    }
}
