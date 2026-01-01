package com.buxhiisd.msg_bypas

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.telephony.SmsManager
import android.util.Log
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel


class MainActivity: FlutterActivity() {
    private val SMS_CHANNEL = "com.buxhiisd.msg_bypas/sms"
    private val ALARM_CHANNEL = "com.buxhiisd.msg_bypas/alarm"
    private val SMS_PERMISSION_CODE = 123

    private var userSafeFlag = false
    private var alarmMethodChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Check if launched with "user_safe" flag
        handleIntent(intent)

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

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        if (intent.getBooleanExtra("user_safe", false)) {
            // Stop alarm service if still running
            stopService(Intent(this, AlarmForegroundService::class.java))

            // Notify Flutter if needed later
            MethodChannel(
                flutterEngine!!.dartExecutor.binaryMessenger,
                "com.buxhiisd.msg_bypas/alarm"
            ).invokeMethod("userSafe", null)
        }
    }


    private fun handleIntent(intent: Intent?) {
        if (intent?.getBooleanExtra("user_safe", false) == true) {
            userSafeFlag = true
            Log.d("MainActivity", "✅ User safe flag detected")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // SMS Channel (keep existing functionality)
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

        // NEW: Alarm Channel for background countdown
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ALARM_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startAlarmService" -> {
                    val duration = call.argument<Int>("duration") ?: 30
                    startAlarmForegroundService(duration)
                    result.success(true)
                }
                "stopAlarmService" -> {
                    stopAlarmForegroundService()
                    result.success(true)
                }
                "turnScreenOn" -> {
                    turnScreenOn()
                    result.success(true)
                }
                "checkUserSafe" -> {
                    val isSafe = userSafeFlag
                    userSafeFlag = false // Reset flag
                    result.success(isSafe)
                }
                else -> result.notImplemented()
            }
        }

        alarmMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ALARM_CHANNEL)
    }

    private fun startAlarmForegroundService(duration: Int) {
        val intent = Intent(this, AlarmForegroundService::class.java).apply {
            putExtra("duration", duration)
            putExtra("flutterEngineId", flutterEngine?.dartExecutor?.isolateServiceId)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopAlarmForegroundService() {
        val intent = Intent(this, AlarmForegroundService::class.java)
        stopService(intent)
    }

    private fun turnScreenOn() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }

        window.addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
        )
    }

    // SMS Methods (keep existing)
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

    private val alarmCancelReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == AlarmForegroundService.ACTION_CANCEL) {
                Log.d("MainActivity", "Received user safe broadcast")
                MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, ALARM_CHANNEL)
                    .invokeMethod("userSafe", null)
            }
        }
    }

    override fun onResume() {
        super.onResume()
        registerReceiver(alarmCancelReceiver, IntentFilter(AlarmForegroundService.ACTION_CANCEL))
    }

    override fun onPause() {
        super.onPause()
        unregisterReceiver(alarmCancelReceiver)
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

        if (requestCode == SMS_PERMISSION_CODE) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                Log.d("SMS", "SMS permission granted")
            } else {
                Log.e("SMS", "SMS permission denied")
            }
        }
    }
}