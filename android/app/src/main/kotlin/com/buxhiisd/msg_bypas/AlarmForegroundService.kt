// android/app/src/main/kotlin/com/buxhiisd/msg_bypas/AlarmForegroundService.kt
package com.buxhiisd.msg_bypas

import android.app.*
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.CountDownTimer
import android.os.IBinder
import androidx.core.app.NotificationCompat

class AlarmForegroundService : Service() {

    private var countDownTimer: CountDownTimer? = null
    private var remainingSeconds = 30
    private var isUserSafe = false

    companion object {
        private const val CHANNEL_ID = "emergency_alarm_channel_silent_v2"  // Changed to force recreation
        private const val NOTIFICATION_ID = 1001
        const val ACTION_USER_SAFE = "com.buxhiisd.msg_bypas.ACTION_USER_SAFE"
    }

    // BroadcastReceiver to handle "I'm Safe" button click
    private val userSafeReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == ACTION_USER_SAFE) {
                println("✅✅✅ USER SAFE BUTTON PRESSED IN SERVICE!")
                handleUserSafe()
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()

        // Delete old notification channels with sound
        deleteOldChannels()

        // Create new silent channel
        createNotificationChannel()

        // Register receiver for "I'm Safe" button
        val filter = IntentFilter(ACTION_USER_SAFE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(userSafeReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(userSafeReceiver, filter)
        }

        println("✅ AlarmForegroundService created and receiver registered")
    }

    private fun deleteOldChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            // List of old channel IDs to delete
            val oldChannels = listOf(
                "emergency_alarm_channel",
                "alarm_countdown_channel",
                "emergency_alarm_channel_v1"
            )

            oldChannels.forEach { channelId ->
                try {
                    notificationManager.deleteNotificationChannel(channelId)
                    println("🗑️ Deleted old channel: $channelId")
                } catch (e: Exception) {
                    println("Channel $channelId not found")
                }
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val duration = intent?.getIntExtra("duration", 30) ?: 30
        remainingSeconds = duration
        isUserSafe = false

        println("🚨 Starting alarm service with $duration seconds countdown")

        // Start foreground with initial notification
        startForeground(NOTIFICATION_ID, createNotification(remainingSeconds))

        // Start countdown
        startCountdown(duration)

        return START_NOT_STICKY
    }

    private fun handleUserSafe() {
        println("✅ Handling user safe in service")
        isUserSafe = true

        // Save to SharedPreferences
        val prefs = getSharedPreferences("app_prefs", Context.MODE_PRIVATE)
        prefs.edit().putBoolean("user_safe_pressed", true).apply()

        // Send broadcast to Flutter
        sendBroadcast(Intent("USER_SAFE_ACTION"))

        // Stop countdown and service
        countDownTimer?.cancel()
        stopForeground(true)
        stopSelf()
    }

    private fun startCountdown(durationSeconds: Int) {
        countDownTimer?.cancel()

        countDownTimer = object : CountDownTimer(
            (durationSeconds * 1000).toLong(),
            1000
        ) {
            override fun onTick(millisUntilFinished: Long) {
                if (isUserSafe) {
                    cancel()
                    return
                }

                remainingSeconds = (millisUntilFinished / 1000).toInt()

                // Check SharedPreferences in case user pressed from MainActivity
                val prefs = getSharedPreferences("app_prefs", Context.MODE_PRIVATE)
                if (prefs.getBoolean("user_safe_pressed", false)) {
                    println("✅ User safe detected via SharedPreferences")
                    isUserSafe = true
                    prefs.edit().putBoolean("user_safe_pressed", false).apply()
                    cancel()
                    stopSelf()
                    return
                }

                // Update notification with countdown
                val notification = createNotification(remainingSeconds)
                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.notify(NOTIFICATION_ID, notification)

                println("⏱️ Countdown: $remainingSeconds seconds")
            }

            override fun onFinish() {
                if (!isUserSafe) {
                    println("⏰ Countdown finished - triggering emergency")
                    sendCompletionBroadcast()
                }
                stopSelf()
            }
        }.start()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            // Delete old channel if it exists
            try {
                notificationManager.deleteNotificationChannel("emergency_alarm_channel")
                println("🗑️ Deleted old notification channel")
            } catch (e: Exception) {
                println("Old channel not found or already deleted")
            }

            val name = "Emergency Alarm (Silent)"
            val descriptionText = "Silent notification with vibration only"
            val importance = NotificationManager.IMPORTANCE_HIGH

            val channel = NotificationChannel(CHANNEL_ID, name, importance).apply {
                description = descriptionText
                // CRITICAL: Set sound to null for silent notification
                setSound(null, null)
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 200, 500)
                setShowBadge(true)
            }

            notificationManager.createNotificationChannel(channel)
            println("✅ Created silent notification channel")
        }
    }

    private fun createNotification(seconds: Int): Notification {
        // Create broadcast intent for "I'm Safe" button
        val userSafeBroadcastIntent = Intent(ACTION_USER_SAFE)
        val userSafePendingIntent = PendingIntent.getBroadcast(
            this,
            0,
            userSafeBroadcastIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Create intent to open app when notification is tapped
        val contentIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        val contentPendingIntent = PendingIntent.getActivity(
            this,
            0,
            contentIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("🚨 ACCIDENT DETECTED!")
            .setContentText("Emergency SMS will be sent in $seconds seconds")
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(false)
            .setContentIntent(contentPendingIntent)
            .setStyle(
                NotificationCompat.BigTextStyle()
                    .bigText("An accident has been detected!\n\nEmergency contacts will be notified in $seconds seconds.\n\nIf you're safe, tap 'I'M SAFE' button below.")
            )
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "I'M SAFE",
                userSafePendingIntent
            )
            .setVibrate(longArrayOf(0, 500, 200, 500))
            // NO SOUND - Sound plays from Flutter app only
            .setSound(null)
            .build()
    }

    private fun sendCompletionBroadcast() {
        val intent = Intent("COUNTDOWN_COMPLETE")
        sendBroadcast(intent)
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            unregisterReceiver(userSafeReceiver)
        } catch (e: Exception) {
            println("Error unregistering receiver: ${e.message}")
        }
        countDownTimer?.cancel()
        println("✅ AlarmForegroundService destroyed")
    }
}