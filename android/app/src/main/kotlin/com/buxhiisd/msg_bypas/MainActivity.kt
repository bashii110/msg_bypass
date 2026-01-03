// android/app/src/main/kotlin/com/buxhiisd/msg_bypas/MainActivity.kt
package com.buxhiisd.msg_bypas

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.telephony.SmsManager
import android.util.Log
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.buxhiisd.msg_bypas/alarm"
    private val SMS_CHANNEL = "com.buxhiisd.msg_bypas/sms"
    private val CALL_CHANNEL = "com.buxhiisd.msg_bypas/call"
    private val SMS_PERMISSION_CODE = 123
    private val CALL_PERMISSION_CODE = 124

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Keep screen on when alarm is triggered
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // SMS Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "sendSMS" -> {
                    val phoneNumber = call.argument<String>("phoneNumber")
                    val message = call.argument<String>("message")

                    if (phoneNumber != null && message != null) {
                        if (hasSmsPermission()) {
                            val success = sendSMSNative(phoneNumber, message)
                            result.success(success)
                        } else {
                            requestSmsPermission()
                            result.error("NO_PERMISSION", "SMS permission not granted", null)
                        }
                    } else {
                        result.error("INVALID_ARGS", "Phone number or message is null", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Call Channel (NEW)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CALL_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "makeCall" -> {
                    val phoneNumber = call.argument<String>("phoneNumber")

                    if (phoneNumber != null) {
                        if (hasCallPermission()) {
                            val success = makePhoneCall(phoneNumber)
                            result.success(success)
                        } else {
                            requestCallPermission()
                            result.error("NO_PERMISSION", "Call permission not granted", null)
                        }
                    } else {
                        result.error("INVALID_ARGS", "Phone number is null", null)
                    }
                }
                "hasCallPermission" -> {
                    result.success(hasCallPermission())
                }
                "requestCallPermission" -> {
                    requestCallPermission()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Alarm Method Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startAlarmService" -> {
                    val duration = call.argument<Int>("duration") ?: 30
                    startAlarmService(duration)
                    result.success(true)
                }
                "stopAlarmService" -> {
                    stopAlarmService()
                    result.success(true)
                }
                "turnScreenOn" -> {
                    turnScreenOn()
                    result.success(true)
                }
                "checkUserSafe" -> {
                    val prefs = getSharedPreferences("app_prefs", Context.MODE_PRIVATE)
                    val userSafe = prefs.getBoolean("user_safe_pressed", false)
                    if (userSafe) {
                        // Reset the flag
                        prefs.edit().putBoolean("user_safe_pressed", false).apply()
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    // CALL METHODS (NEW)
    private fun hasCallPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.CALL_PHONE
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    private fun requestCallPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.CALL_PHONE),
                CALL_PERMISSION_CODE
            )
        }
    }

    private fun makePhoneCall(phoneNumber: String): Boolean {
        return try {
            if (!hasCallPermission()) {
                Log.e("CALL", "No call permission")
                return false
            }

            Log.d("CALL", "Initiating call to $phoneNumber")

            val callIntent = Intent(Intent.ACTION_CALL).apply {
                data = Uri.parse("tel:$phoneNumber")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }

            startActivity(callIntent)
            Log.d("CALL", "Call initiated successfully to $phoneNumber")
            true

        } catch (e: Exception) {
            Log.e("CALL", "Failed to make call: ${e.message}")
            e.printStackTrace()
            false
        }
    }

    private fun startAlarmService(duration: Int) {
        // Clear any previous "user safe" flag
        val prefs = getSharedPreferences("app_prefs", Context.MODE_PRIVATE)
        prefs.edit().putBoolean("user_safe_pressed", false).apply()

        val serviceIntent = Intent(this, AlarmForegroundService::class.java)
        serviceIntent.putExtra("duration", duration)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }

        Log.d("MainActivity", "✅ Alarm service started with duration: $duration seconds")
    }

    private fun stopAlarmService() {
        val serviceIntent = Intent(this, AlarmForegroundService::class.java)
        stopService(serviceIntent)
        Log.d("MainActivity", "✅ Alarm service stopped")
    }

    private fun turnScreenOn() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }

        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                    PowerManager.ACQUIRE_CAUSES_WAKEUP,
            "EmergencyApp:WakeLock"
        )
        wakeLock?.acquire(10 * 60 * 1000L) // 10 minutes

        Log.d("MainActivity", "✅ Screen turned on")
    }

    // SMS Methods
    private fun hasSmsPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.SEND_SMS
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    private fun requestSmsPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.SEND_SMS),
                SMS_PERMISSION_CODE
            )
        }
    }

    private fun sendSMSNative(phoneNumber: String, message: String): Boolean {
        return try {
            if (!hasSmsPermission()) {
                Log.e("SMS", "No SMS permission")
                return false
            }

            Log.d("SMS", "Attempting to send SMS to $phoneNumber")

            val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val context = applicationContext
                context.getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }

            if (message.length > 160) {
                Log.d("SMS", "Message is long, dividing into parts")
                val parts = smsManager.divideMessage(message)
                smsManager.sendMultipartTextMessage(
                    phoneNumber,
                    null,
                    parts,
                    null,
                    null
                )
            } else {
                Log.d("SMS", "Sending single SMS")
                smsManager.sendTextMessage(
                    phoneNumber,
                    null,
                    message,
                    null,
                    null
                )
            }

            Log.d("SMS", "SMS sent successfully to $phoneNumber")
            true

        } catch (e: Exception) {
            Log.e("SMS", "Failed to send SMS: ${e.message}")
            e.printStackTrace()
            false
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        when (requestCode) {
            SMS_PERMISSION_CODE -> {
                if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                    Log.d("SMS", "SMS permission granted")
                } else {
                    Log.e("SMS", "SMS permission denied")
                }
            }
            CALL_PERMISSION_CODE -> {
                if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                    Log.d("CALL", "Call permission granted")
                } else {
                    Log.e("CALL", "Call permission denied")
                }
            }
        }
    }
}