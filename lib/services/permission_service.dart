import 'package:permission_handler/permission_handler.dart';
import 'package:telephony/telephony.dart';

class PermissionService {
  static final Telephony telephony = Telephony.instance;

  static Future<bool> requestAllPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.sms,
      Permission.phone,
      Permission.location,
      Permission.locationAlways,
      Permission.notification,
    ].request();

    bool allGranted = statuses.values.every((status) => status.isGranted);
    return allGranted;
  }

  static Future<bool> checkSMSPermissions() async {
    return await Permission.sms.isGranted;
  }

  static Future<bool> checkLocationPermissions() async {
    bool location = await Permission.location.isGranted;
    bool locationAlways = await Permission.locationAlways.isGranted;
    return location || locationAlways;
  }

  static Future<bool> requestSMSPermissions() async {
    PermissionStatus status = await Permission.sms.request();
    return status.isGranted;
  }

  static Future<bool> requestLocationPermissions() async {
    PermissionStatus location = await Permission.location.request();

    if (location.isGranted) {
      PermissionStatus locationAlways = await Permission.locationAlways.request();
      return locationAlways.isGranted || location.isGranted;
    }

    return false;
  }

  static Future<bool> requestDefaultSMSApp() async {
    try {
      final bool? result = await telephony.requestSmsPermissions;
      return result ?? false;
    } catch (e) {
      print('Error requesting SMS permissions: $e');
      return false;
    }
  }

  static Future<bool> isDefaultSMSApp() async {
    try {
      final bool? result = await telephony.isSmsCapable;
      return result ?? false;
    } catch (e) {
      print('Error checking SMS capability: $e');
      return false;
    }
  }

  static Future<Map<String, bool>> checkAllPermissions() async {
    return {
      'sms': await Permission.sms.isGranted,
      'phone': await Permission.phone.isGranted,
      'location': await Permission.location.isGranted,
      'locationAlways': await Permission.locationAlways.isGranted,
      'notification': await Permission.notification.isGranted,
    };
  }

  static Future<bool> openAppSettings() async {
    return await openAppSettings();
  }
}