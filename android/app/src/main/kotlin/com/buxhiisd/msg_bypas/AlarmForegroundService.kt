package com.buxhiisd.msg_bypas

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*

class AlarmForegroundService : Service() {

    private var wakeLock: PowerManager.WakeLock? = null
    private var countdownJob: Job? = null
    private var remainingSeconds = 30

    private val NOTIFICATION_ID = 1001
    private val CHANNEL_ID = "alarm_countdown_channel"

    companion object {
        const val ACTION_CANCEL = "com.buxhiisd.msg_bypas.CANCEL_ALARM"
        const val ACTION_COUNTDOWN_COMPLETE = "com.buxhiisd.msg_bypas.COUNTDOWN_COMPLETE"
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        acquireWakeLock()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {

        // ✅ USER PRESSED "I'M SAFE"
        if (intent?.action == ACTION_CANCEL) {
            Log.d("AlarmService", "🛑 Alarm cancelled by user")
            stopAlarm()
            stopForeground(true)
            sendBroadcast(Intent(ACTION_CANCEL))
            stopSelf()
            return START_NOT_STICKY
        }

        // ✅ NORMAL START
        startForeground(NOTIFICATION_ID, createNotification(remainingSeconds))
        startCountdown()

        return START_STICKY
    }

    // ✅ THIS IS STEP 3 (PROPER STOP)
    private fun stopAlarm() {
        countdownJob?.cancel()
        countdownJob = null

        wakeLock?.let {
            if (it.isHeld) it.release()
        }

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(NOTIFICATION_ID)
    }

    private fun startCountdown() {
        countdownJob?.cancel()

        countdownJob = CoroutineScope(Dispatchers.Default).launch {
            while (remainingSeconds > 0 && isActive) {
                delay(1000)
                remainingSeconds--

                withContext(Dispatchers.Main) {
                    updateNotification(remainingSeconds)
                }
            }

            if (remainingSeconds <= 0) {
                sendBroadcast(Intent(ACTION_COUNTDOWN_COMPLETE))
                launchAppForSMS()
                stopSelf()
            }
        }
    }

    private fun launchAppForSMS() {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("trigger_sms", true)
        }
        startActivity(intent)
    }

    private fun createNotification(seconds: Int): Notification {

        val cancelIntent = Intent(this, AlarmForegroundService::class.java).apply {
            action = ACTION_CANCEL
        }

        val cancelPendingIntent = PendingIntent.getService(
            this,
            0,
            cancelIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("🚨 ACCIDENT DETECTED")
            .setContentText("Emergency SMS in $seconds seconds")
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setOngoing(true)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "I'm Safe",
                cancelPendingIntent
            )
            .build()
    }

    private fun updateNotification(seconds: Int) {
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, createNotification(seconds))
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Emergency Alarm",
                NotificationManager.IMPORTANCE_HIGH
            )
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
    }

    private fun acquireWakeLock() {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "RescueMe::WakeLock"
        ).apply { acquire(40_000) }
    }

    override fun onDestroy() {
        stopAlarm()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
