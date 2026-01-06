package com.buxhiisd.msg_bypas

import android.app.*
import android.content.Context
import android.content.Intent
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import kotlin.math.sqrt

class AccidentMonitoringService : Service(), SensorEventListener {

    private lateinit var sensorManager: SensorManager
    private var accelerometer: Sensor? = null
    private var gyroscope: Sensor? = null
    private var wakeLock: PowerManager.WakeLock? = null

    private var accelerateX = 0.0
    private var accelerateY = 0.0
    private var accelerateZ = 0.0
    private var gyroscopeX = 0.0
    private var gyroscopeY = 0.0
    private var gyroscopeZ = 0.0

    private val recentAccelerations = mutableListOf<Double>()
    private var highAccelerationCount = 0

    private var isAccidentDetected = false

    companion object {
        private const val CHANNEL_ID = "accident_monitoring_channel"
        private const val NOTIFICATION_ID = 2001
        private const val TAG = "AccidentMonitoringService"

        // Thresholds - ADJUSTED FOR BETTER DETECTION
        private const val HIGH_ACCELERATION_THRESHOLD = 20.0
        private const val MEDIUM_ACCELERATION_THRESHOLD = 15.0
        private const val GYROSCOPE_THRESHOLD = 3.0
        private const val REQUIRED_SAMPLES = 2
        private const val SMOOTH_WINDOW = 5
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "✅ Service created")

        // Acquire wake lock to keep CPU running
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "RescueMe::AccidentMonitorWakeLock"
        )
        wakeLock?.acquire(10 * 60 * 60 * 1000L) // 10 hours

        createNotificationChannel()
        setupSensors()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "🚀 Service started")

        val notification = createNotification("Monitoring for accidents...")
        startForeground(NOTIFICATION_ID, notification)

        return START_STICKY // Restart if killed by system
    }

    private fun setupSensors() {
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager

        accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        gyroscope = sensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE)

        accelerometer?.let {
            sensorManager.registerListener(
                this,
                it,
                SensorManager.SENSOR_DELAY_GAME
            )
            Log.d(TAG, "✅ Accelerometer registered")
        }

        gyroscope?.let {
            sensorManager.registerListener(
                this,
                it,
                SensorManager.SENSOR_DELAY_GAME
            )
            Log.d(TAG, "✅ Gyroscope registered")
        }

        if (accelerometer == null) {
            Log.e(TAG, "❌ No accelerometer found!")
        }
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (isAccidentDetected) return

        event?.let {
            when (it.sensor.type) {
                Sensor.TYPE_ACCELEROMETER -> {
                    accelerateX = it.values[0].toDouble()
                    accelerateY = it.values[1].toDouble()
                    accelerateZ = it.values[2].toDouble()
                    checkForAccident()
                }
                Sensor.TYPE_GYROSCOPE -> {
                    gyroscopeX = it.values[0].toDouble()
                    gyroscopeY = it.values[1].toDouble()
                    gyroscopeZ = it.values[2].toDouble()
                }
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        // Not needed
    }

    private fun checkForAccident() {
        val accelerationMagnitude = sqrt(
            accelerateX * accelerateX +
                    accelerateY * accelerateY +
                    accelerateZ * accelerateZ
        )

        val gyroscopeMagnitude = sqrt(
            gyroscopeX * gyroscopeX +
                    gyroscopeY * gyroscopeY +
                    gyroscopeZ * gyroscopeZ
        )

        recentAccelerations.add(accelerationMagnitude)
        if (recentAccelerations.size > SMOOTH_WINDOW) {
            recentAccelerations.removeAt(0)
        }

        if (recentAccelerations.isEmpty()) return

        val avgAccel = recentAccelerations.average()

        // Ignore very low values
        if (avgAccel < 10.0) return
        if (gyroscopeMagnitude < 0.3) return

        // Track high acceleration
        if (avgAccel > MEDIUM_ACCELERATION_THRESHOLD) {
            highAccelerationCount++
        } else {
            highAccelerationCount = 0
        }

        // Detection logic
        val highImpact = avgAccel > HIGH_ACCELERATION_THRESHOLD &&
                highAccelerationCount >= REQUIRED_SAMPLES

        val rollover = gyroscopeMagnitude > GYROSCOPE_THRESHOLD &&
                highAccelerationCount >= REQUIRED_SAMPLES

        if (highImpact || rollover) {
            Log.w(TAG, "🚨 ACCIDENT DETECTED! Magnitude: $avgAccel, Gyro: $gyroscopeMagnitude")
            triggerAccident()
        }
    }

    private fun triggerAccident() {
        isAccidentDetected = true
        highAccelerationCount = 0

        // Notify Flutter app
        val intent = Intent("ACCIDENT_DETECTED_BACKGROUND")
        sendBroadcast(intent)

        // Update notification
        updateNotification("🚨 ACCIDENT DETECTED! Opening app...")

        // Launch MainActivity
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("accident_detected", true)
        }
        startActivity(launchIntent)

        // Reset after 5 seconds
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            isAccidentDetected = false
            updateNotification("Monitoring for accidents...")
        }, 5000)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "Accident Monitoring"
            val descriptionText = "Background accident detection service"
            val importance = NotificationManager.IMPORTANCE_LOW
            val channel = NotificationChannel(CHANNEL_ID, name, importance).apply {
                description = descriptionText
                setSound(null, null)
            }

            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(text: String): Notification {
        val notificationIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, notificationIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Rescue Me - Active")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun updateNotification(text: String) {
        val notification = createNotification(text)
        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    override fun onDestroy() {
        super.onDestroy()
        sensorManager.unregisterListener(this)
        wakeLock?.release()
        Log.d(TAG, "✅ Service destroyed")
    }

    override fun onBind(intent: Intent?): IBinder? = null
}