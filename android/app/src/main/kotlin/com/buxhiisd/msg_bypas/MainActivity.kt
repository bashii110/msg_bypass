package com.buxhiisd.msg_bypas

import android.Manifest
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
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
    private val SERVICE_CHANNEL = "com.buxhiisd.msg_bypas/service"

    private val SMS_PERMISSION_CODE = 123
    private val CALL_PERMISSION_CODE = 124
    private val ALL_PERMISSIONS_CODE = 125

    private var wakeLock: PowerManager.WakeLock? = null

    // SMS delivery tracking
    private val SMS_SENT = "SMS_SENT"
    private val SMS_DELIVERED = "SMS_DELIVERED"

    // Track SMS send results
    private val smsSendResults = mutableMapOf<String, Boolean>()

    private val smsSentReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val phoneNumber = intent?.getStringExtra("phoneNumber") ?: "unknown"
            when (resultCode) {
                RESULT_OK -> {
                    Log.d("SMS", "✅ SMS sent successfully to $phoneNumber")
                    smsSendResults[phoneNumber] = true
                }
                SmsManager.RESULT_ERROR_GENERIC_FAILURE -> {
                    Log.e("SMS", "❌ Generic failure for $phoneNumber")
                    smsSendResults[phoneNumber] = false
                }
                SmsManager.RESULT_ERROR_NO_SERVICE -> {
                    Log.e("SMS", "❌ No service for $phoneNumber")
                    smsSendResults[phoneNumber] = false
                }
                SmsManager.RESULT_ERROR_NULL_PDU -> {
                    Log.e("SMS", "❌ Null PDU for $phoneNumber")
                    smsSendResults[phoneNumber] = false
                }
                SmsManager.RESULT_ERROR_RADIO_OFF -> {
                    Log.e("SMS", "❌ Radio off for $phoneNumber")
                    smsSendResults[phoneNumber] = false
                }
            }
        }
    }

    private val smsDeliveredReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val phoneNumber = intent?.getStringExtra("phoneNumber") ?: "unknown"
            when (resultCode) {
                RESULT_OK -> Log.d("SMS", "✅ SMS delivered to $phoneNumber")
                else -> Log.e("SMS", "❌ SMS not delivered to $phoneNumber")
            }
        }
    }

    private val accidentReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == "ACCIDENT_DETECTED_BACKGROUND") {
                Log.d("MainActivity", "🚨 Received accident detection from background service")
                flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                    MethodChannel(messenger, CHANNEL).invokeMethod("onAccidentDetectedBackground", null)
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Register SMS receivers
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(smsSentReceiver, IntentFilter(SMS_SENT), Context.RECEIVER_NOT_EXPORTED)
                registerReceiver(smsDeliveredReceiver, IntentFilter(SMS_DELIVERED), Context.RECEIVER_NOT_EXPORTED)
                registerReceiver(accidentReceiver, IntentFilter("ACCIDENT_DETECTED_BACKGROUND"), Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(smsSentReceiver, IntentFilter(SMS_SENT))
                registerReceiver(smsDeliveredReceiver, IntentFilter(SMS_DELIVERED))
                registerReceiver(accidentReceiver, IntentFilter("ACCIDENT_DETECTED_BACKGROUND"))
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error registering receivers: ${e.message}")
        }

        // REMOVED: checkManufacturerAndRequestPermissions()
        // Don't automatically request permissions on app launch
        // Let Flutter handle when to show these

        if (intent?.getBooleanExtra("accident_detected", false) == true) {
            Log.d("MainActivity", "🚨 App launched due to accident detection")
        }

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
        try {
            unregisterReceiver(smsSentReceiver)
            unregisterReceiver(smsDeliveredReceiver)
            unregisterReceiver(accidentReceiver)
        } catch (e: Exception) {
            Log.e("MainActivity", "Error unregistering receivers: ${e.message}")
        }
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
            }
        }
    }

    // FIXED: Only open settings when explicitly requested by user
    private fun requestAutoStartPermission() {
        try {
            val manufacturer = Build.MANUFACTURER.lowercase()
            Log.d("SMS", "📱 Requesting autostart for: $manufacturer")

            val intent = when {
                manufacturer.contains("vivo") -> {
                    Intent().apply {
                        component = android.content.ComponentName(
                            "com.vivo.permissionmanager",
                            "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"
                        )
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                }
                manufacturer.contains("oppo") || manufacturer.contains("realme") -> {
                    Intent().apply {
                        component = android.content.ComponentName(
                            "com.coloros.safecenter",
                            "com.coloros.safecenter.permission.startup.StartupAppListActivity"
                        )
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                }
                manufacturer.contains("xiaomi") || manufacturer.contains("redmi") -> {
                    Intent().apply {
                        component = android.content.ComponentName(
                            "com.miui.securitycenter",
                            "com.miui.permcenter.autostart.AutoStartManagementActivity"
                        )
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                }
                manufacturer.contains("huawei") -> {
                    Intent().apply {
                        component = android.content.ComponentName(
                            "com.huawei.systemmanager",
                            "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
                        )
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                }
                else -> {
                    // For other manufacturers, open app settings
                    Log.d("SMS", "⚠️ Unknown manufacturer, opening app settings")
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = Uri.parse("package:$packageName")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                }
            }

            try {
                startActivity(intent)
                Log.d("SMS", "✅ Opened autostart/settings")
            } catch (e: Exception) {
                Log.e("SMS", "❌ Failed to open autostart: ${e.message}")
                // Don't fallback to app settings automatically
                // Let the user know via Flutter
                showToast("Unable to open autostart settings. Please enable manually in Settings → Apps.")
            }

        } catch (e: Exception) {
            Log.e("SMS", "❌ Error in requestAutoStartPermission: ${e.message}")
        }
    }

    private fun showToast(message: String) {
        android.widget.Toast.makeText(this, message, android.widget.Toast.LENGTH_LONG).show()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Service Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SERVICE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startMonitoringService" -> {
                    startMonitoringService()
                    result.success(true)
                }
                "stopMonitoringService" -> {
                    stopMonitoringService()
                    result.success(true)
                }
                "isBatteryOptimized" -> {
                    result.success(isBatteryOptimized())
                }
                "requestIgnoreBatteryOptimization" -> {
                    requestIgnoreBatteryOptimization()
                    result.success(true)
                }
                "requestAutoStartPermission" -> {
                    requestAutoStartPermission()
                    result.success(true)
                }
                "openAppSettings" -> {
                    openAppSettings()
                    result.success(true)
                }
                "isChineseOEM" -> {
                    result.success(isChineseOEM())
                }
                else -> result.notImplemented()
            }
        }

        // SMS Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "sendSMS" -> {
                    val phoneNumber = call.argument<String>("phoneNumber")
                    val message = call.argument<String>("message")

                    if (phoneNumber != null && message != null) {
                        if (hasSmsPermission()) {
                            val success = sendSMSWithRetry(phoneNumber, message)
                            result.success(success)
                        } else {
                            requestAllPermissions()
                            result.error("NO_PERMISSION", "SMS permission not granted", null)
                        }
                    } else {
                        result.error("INVALID_ARGS", "Phone number or message is null", null)
                    }
                }
                "hasSmsPermission" -> {
                    result.success(hasSmsPermission())
                }
                "requestSmsPermission" -> {
                    requestAllPermissions()
                    result.success(true)
                }
                "getDeviceInfo" -> {
                    result.success(mapOf(
                        "manufacturer" to Build.MANUFACTURER,
                        "model" to Build.MODEL,
                        "android" to Build.VERSION.RELEASE,
                        "sdk" to Build.VERSION.SDK_INT,
                        "isChineseOEM" to isChineseOEM()
                    ))
                }
                else -> result.notImplemented()
            }
        }

        // Call Channel
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

        // Alarm Channel
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

    private fun isChineseOEM(): Boolean {
        val manufacturer = Build.MANUFACTURER.lowercase()
        return manufacturer.contains("vivo") ||
                manufacturer.contains("oppo") ||
                manufacturer.contains("realme") ||
                manufacturer.contains("oneplus") ||
                manufacturer.contains("xiaomi") ||
                manufacturer.contains("redmi") ||
                manufacturer.contains("huawei")
    }

    private fun openAppSettings() {
        try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            Log.d("MainActivity", "✅ Opened app settings")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Failed to open app settings: ${e.message}")
        }
    }

    private fun startMonitoringService() {
        val serviceIntent = Intent(this, AccidentMonitoringService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
        Log.d("MainActivity", "✅ Background monitoring service started")
    }

    private fun stopMonitoringService() {
        val serviceIntent = Intent(this, AccidentMonitoringService::class.java)
        stopService(serviceIntent)
        Log.d("MainActivity", "⏸️ Background monitoring service stopped")
    }

    private fun isBatteryOptimized(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            return !powerManager.isIgnoringBatteryOptimizations(packageName)
        }
        return false
    }

    private fun requestIgnoreBatteryOptimization() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                }
                startActivity(intent)
            } catch (e: Exception) {
                Log.e("MainActivity", "Error opening battery optimization settings: ${e.message}")
            }
        }
    }

    private fun hasCallPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            ContextCompat.checkSelfPermission(this, Manifest.permission.CALL_PHONE) == PackageManager.PERMISSION_GRANTED
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
            Log.d("CALL", "✅ Call initiated successfully")
            true
        } catch (e: Exception) {
            Log.e("CALL", "❌ Failed to make call: ${e.message}")
            false
        }
    }

    private fun startAlarmService(duration: Int) {
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
            PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
            "EmergencyApp:WakeLock"
        )
        wakeLock?.acquire(10 * 60 * 1000L)
        Log.d("MainActivity", "✅ Screen turned on")
    }

    // SMS Methods
    private fun hasSmsPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true

        val perms = arrayOf(
            Manifest.permission.SEND_SMS,
            Manifest.permission.READ_PHONE_STATE
        )

        return perms.all {
            ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requestAllPermissions() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val permissions = arrayOf(
                Manifest.permission.SEND_SMS,
                Manifest.permission.READ_SMS,
                Manifest.permission.RECEIVE_SMS,
                Manifest.permission.READ_PHONE_STATE,
                Manifest.permission.CALL_PHONE
            )

            ActivityCompat.requestPermissions(this, permissions, ALL_PERMISSIONS_CODE)
        }
    }

    private fun sendSMSWithRetry(phoneNumber: String, message: String, retryCount: Int = 3): Boolean {
        for (attempt in 1..retryCount) {
            Log.d("SMS", "📱 Attempt $attempt/$retryCount to send SMS to $phoneNumber")

            val success = sendSMSNative(phoneNumber, message)

            if (success) {
                Log.d("SMS", "✅ SMS sent successfully on attempt $attempt")
                return true
            }

            if (attempt < retryCount) {
                Log.d("SMS", "⏳ Waiting before retry...")
                Thread.sleep(2000)
            }
        }

        Log.e("SMS", "❌ Failed to send SMS after $retryCount attempts")
        return false
    }

    private fun sendSMSNative(phoneNumber: String, message: String): Boolean {
        return try {
            if (!hasSmsPermission()) {
                Log.e("SMS", "❌ No SMS permission")
                return false
            }

            Log.d("SMS", "📱 Sending SMS to $phoneNumber")
            Log.d("SMS", "📝 Message length: ${message.length} characters")

            val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                applicationContext.getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }

            val sentPI = PendingIntent.getBroadcast(
                this,
                phoneNumber.hashCode(),
                Intent(SMS_SENT).apply {
                    putExtra("phoneNumber", phoneNumber)
                },
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                else
                    PendingIntent.FLAG_UPDATE_CURRENT
            )

            val deliveredPI = PendingIntent.getBroadcast(
                this,
                phoneNumber.hashCode() + 1,
                Intent(SMS_DELIVERED).apply {
                    putExtra("phoneNumber", phoneNumber)
                },
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                else
                    PendingIntent.FLAG_UPDATE_CURRENT
            )

            smsSendResults.remove(phoneNumber)

            if (message.length > 160) {
                Log.d("SMS", "📨 Sending multipart SMS (${message.length} chars)")
                val parts = smsManager.divideMessage(message)
                val sentIntents = ArrayList<PendingIntent>()
                val deliveredIntents = ArrayList<PendingIntent>()

                for (i in parts.indices) {
                    sentIntents.add(sentPI)
                    deliveredIntents.add(deliveredPI)
                }

                smsManager.sendMultipartTextMessage(
                    phoneNumber,
                    null,
                    parts,
                    sentIntents,
                    deliveredIntents
                )
            } else {
                Log.d("SMS", "📨 Sending single SMS")
                smsManager.sendTextMessage(
                    phoneNumber,
                    null,
                    message,
                    sentPI,
                    deliveredPI
                )
            }

            Thread.sleep(1000)

            val result = smsSendResults[phoneNumber]
            if (result == true) {
                Log.d("SMS", "✅ SMS confirmed sent to $phoneNumber")
                return true
            } else if (result == false) {
                Log.e("SMS", "❌ SMS confirmed failed for $phoneNumber")
                return false
            } else {
                Log.d("SMS", "⏳ SMS queued successfully to $phoneNumber")
                return true
            }

        } catch (e: SecurityException) {
            Log.e("SMS", "❌ Security exception: ${e.message}")
            false
        } catch (e: Exception) {
            Log.e("SMS", "❌ Failed to send SMS: ${e.message}")
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
            SMS_PERMISSION_CODE, ALL_PERMISSIONS_CODE -> {
                val allGranted = grantResults.all { it == PackageManager.PERMISSION_GRANTED }
                if (allGranted) {
                    Log.d("PERMISSION", "✅ All permissions granted")
                } else {
                    Log.e("PERMISSION", "❌ Some permissions denied")
                }
            }
            CALL_PERMISSION_CODE -> {
                if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                    Log.d("CALL", "✅ Call permission granted")
                } else {
                    Log.e("CALL", "❌ Call permission denied")
                }
            }
        }
    }
}