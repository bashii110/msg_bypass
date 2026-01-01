import 'package:geolocator/geolocator.dart';
import 'package:telephony/telephony.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'location_service.dart';

class SMSService {
  static final Telephony telephony = Telephony.instance;
  static const platform = MethodChannel('com.buxhiisd.msg_bypas/sms');

  /// Check if device is OPPO or Vivo
  static Future<bool> isOppoOrVivo() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final manufacturer = androidInfo.manufacturer.toLowerCase();
      return manufacturer.contains('oppo') ||
          manufacturer.contains('vivo') ||
          manufacturer.contains('realme') ||
          manufacturer.contains('oneplus');
    } catch (e) {
      return false;
    }
  }

  /// Send SMS with direct method (bypasses restrictions better)
  static Future<bool> sendSMS(String phoneNumber, String message) async {
    try {
      // Method 1: Try native Android SMS Manager directly
      bool success = await _sendViaNativeSmsManager(phoneNumber, message);
      if (success) {
        print('SMS sent via native manager');
        return true;
      }

      // Method 2: Try standard telephony package
      success = await _sendViaTelephony(phoneNumber, message);
      if (success) {
        print('SMS sent via telephony');
        return true;
      }

      // Method 3: Last resort - open SMS app (this is what's happening now)
      print('Opening SMS app as fallback');
      await _openSMSApp(phoneNumber, message);
      return true;

    } catch (e) {
      print('All SMS methods failed: $e');
      return false;
    }
  }

  /// Method 1: Use native Android SMS Manager via platform channel
  static Future<bool> _sendViaNativeSmsManager(String phoneNumber, String message) async {
    try {
      final result = await platform.invokeMethod('sendSMS', {
        'phoneNumber': phoneNumber,
        'message': message,
      });
      return result == true;
    } catch (e) {
      print('Native SMS manager failed: $e');
      return false;
    }
  }

  /// Method 2: Standard telephony with better error handling
  static Future<bool> _sendViaTelephony(String phoneNumber, String message) async {
    try {
      // Check if we have permission
      final hasPermission = await Permission.sms.isGranted;
      if (!hasPermission) {
        print('SMS permission not granted');
        return false;
      }

      // Try sending
      await telephony.sendSms(
        to: phoneNumber,
        message: message,
        isMultipart: message.length > 160,
        statusListener: (SendStatus status) {
          print('SMS Status: $status');
        },
      );

      // Wait to confirm
      await Future.delayed(const Duration(seconds: 1));
      return true;
    } catch (e) {
      print('Telephony method failed: $e');
      return false;
    }
  }

  /// Method 3: Open SMS app with pre-filled message
  static Future<void> _openSMSApp(String phoneNumber, String message) async {
    final Uri smsUri = Uri(
      scheme: 'sms',
      path: phoneNumber,
      queryParameters: {'body': message},
    );

    await launchUrl(smsUri, mode: LaunchMode.externalApplication);
  }

  /// Send emergency SMS with automatic fallback
  static Future<bool> sendEmergencySMS(String phoneNumber, {required String message}) async {

    try {
      String message = await LocationService.getFullLocationMessage();
      return await sendSMS(phoneNumber, message);
    } catch (e) {
      print('Error sending emergency SMS: $e');
      return await sendSMS(
        phoneNumber,
        '🚨 EMERGENCY 🚨\nAccident detected! Unable to get location. Please send help!',
      );
    }
  }

  /// Quick emergency SMS with better error handling
  static Future<bool> sendQuickEmergencySMS(String phoneNumber) async {
    try {
      Position? position = await LocationService.getCurrentLocation()
          .timeout(const Duration(seconds: 5));

      String message;
      if (position == null) {
        message = '🚨 EMERGENCY 🚨\nAccident detected! Unable to get location. Please send help!';
      } else {
        message = LocationService.getQuickLocationMessage(position);
      }

      return await sendSMS(phoneNumber, message);
    } catch (e) {
      print('Error sending quick emergency SMS: $e');
      return await sendSMS(
        phoneNumber,
        '🚨 EMERGENCY ALERT 🚨\nPlease send help immediately!',
      );
    }
  }

  static Future<List<Map<String, dynamic>>> getInboxMessages() async {
    try {
      List<SmsMessage> messages = await telephony.getInboxSms(
        columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
      );

      return messages.map((msg) => {
        'address': msg.address ?? 'Unknown',
        'body': msg.body ?? '',
        'date': msg.date ?? DateTime.now(),
      }).toList();
    } catch (e) {
      print('Error getting inbox messages: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getSentMessages() async {
    try {
      List<SmsMessage> messages = await telephony.getSentSms(
        columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
      );

      return messages.map((msg) => {
        'address': msg.address ?? 'Unknown',
        'body': msg.body ?? '',
        'date': msg.date ?? DateTime.now(),
      }).toList();
    } catch (e) {
      print('Error getting sent messages: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getConversation(String address) async {
    try {
      List<SmsMessage> messages = await telephony.getInboxSms(
        columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE, SmsColumn.TYPE],
        filter: SmsFilter.where(SmsColumn.ADDRESS).equals(address),
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
      );

      return messages.map((msg) => {
        'address': msg.address ?? 'Unknown',
        'body': msg.body ?? '',
        'date': msg.date ?? DateTime.now(),
        'type': msg.type ?? SmsType.MESSAGE_TYPE_INBOX,
      }).toList();
    } catch (e) {
      print('Error getting conversation: $e');
      return [];
    }
  }
}