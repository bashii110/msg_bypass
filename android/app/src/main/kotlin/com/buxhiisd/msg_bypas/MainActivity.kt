package com.buxhiisd.msg_bypas

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.SmsManager
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.buxhiisd.msg_bypas/sms"
    private val SMS_PERMISSION_CODE = 123

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "sendSMS" -> {
                    val phoneNumber = call.argument<String>("phoneNumber")
                    val message = call.argument<String>("message")

                    if (phoneNumber != null && message != null) {
                        // Check permission first
                        if (hasSmsPermission()) {
                            val success = sendSMSNative(phoneNumber, message)
                            result.success(success)
                        } else {
                            // Request permission if not granted
                            requestSmsPermission()
                            result.error("NO_PERMISSION", "SMS permission not granted", null)
                        }
                    } else {
                        result.error("INVALID_ARGS", "Phone number or message is null", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

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
            // Double-check permission
            if (!hasSmsPermission()) {
                Log.e("SMS", "No SMS permission")
                return false
            }

            Log.d("SMS", "Attempting to send SMS to $phoneNumber")

            val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                // Android 12 and above
                val context = applicationContext
                context.getSystemService(SmsManager::class.java)
            } else {
                // Below Android 12
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }

            // For long messages, divide into parts
            if (message.length > 160) {
                Log.d("SMS", "Message is long, dividing into parts")
                val parts = smsManager.divideMessage(message)
                smsManager.sendMultipartTextMessage(
                    phoneNumber,
                    null,
                    parts,
                    null,  // sentIntents
                    null   // deliveryIntents
                )
            } else {
                Log.d("SMS", "Sending single SMS")
                smsManager.sendTextMessage(
                    phoneNumber,
                    null,
                    message,
                    null,  // sentIntent
                    null   // deliveryIntent
                )
            }

            Log.d("SMS", "SMS sent successfully to $phoneNumber")
            true

        } catch (e: SecurityException) {
            Log.e("SMS", "Security exception - SMS permission issue: ${e.message}")
            e.printStackTrace()
            false
        } catch (e: IllegalArgumentException) {
            Log.e("SMS", "Invalid phone number or message: ${e.message}")
            e.printStackTrace()
            false
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