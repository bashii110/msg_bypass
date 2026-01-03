// lib/services/call_service.dart
import 'package:flutter/services.dart';

class CallService {
  static const platform = MethodChannel('com.buxhiisd.msg_bypas/call');

  /// Make an emergency call to a phone number
  static Future<bool> makeEmergencyCall(String phoneNumber) async {
    try {
      print("📞 Attempting to call: $phoneNumber");

      final bool result = await platform.invokeMethod('makeCall', {
        'phoneNumber': phoneNumber,
      });

      if (result) {
        print("✅ Call initiated to $phoneNumber");
      } else {
        print("❌ Failed to initiate call to $phoneNumber");
      }

      return result;
    } catch (e) {
      print("❌ Call error: $e");
      return false;
    }
  }

  /// Make calls to multiple numbers sequentially with delay
  static Future<void> makeEmergencyCalls(List<String> phoneNumbers, {
    Duration delayBetweenCalls = const Duration(seconds: 3),
  }) async {
    if (phoneNumbers.isEmpty) {
      print("⚠️ No phone numbers provided for calling");
      return;
    }

    print("📞 Starting emergency calls to ${phoneNumbers.length} contacts");

    for (int i = 0; i < phoneNumbers.length; i++) {
      final phoneNumber = phoneNumbers[i];

      print("📞 Calling contact ${i + 1}/${phoneNumbers.length}: $phoneNumber");

      final success = await makeEmergencyCall(phoneNumber);

      if (success) {
        print("✅ Call ${i + 1} successful");

        // Wait before next call (except for last one)
        if (i < phoneNumbers.length - 1) {
          print("⏳ Waiting ${delayBetweenCalls.inSeconds} seconds before next call...");
          await Future.delayed(delayBetweenCalls);
        }
      } else {
        print("❌ Call ${i + 1} failed");
      }
    }

    print("✅ Emergency calling completed");
  }

  /// Check if phone call permission is granted
  static Future<bool> hasCallPermission() async {
    try {
      final bool result = await platform.invokeMethod('hasCallPermission');
      return result;
    } catch (e) {
      print("❌ Permission check error: $e");
      return false;
    }
  }

  /// Request phone call permission
  static Future<bool> requestCallPermission() async {
    try {
      final bool result = await platform.invokeMethod('requestCallPermission');
      return result;
    } catch (e) {
      print("❌ Permission request error: $e");
      return false;
    }
  }
}