import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'sms_service.dart';

class AccidentDetectionService {
  static final AccidentDetectionService _instance = AccidentDetectionService._internal();
  factory AccidentDetectionService() => _instance;
  AccidentDetectionService._internal();

  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  bool _isMonitoring = false;
  bool _accidentDetected = false;
  DateTime? _lastAlertTime;

  // Thresholds for accident detection
  static const double HIGH_IMPACT_THRESHOLD = 30.0; // m/s²
  static const double SUSTAINED_IMPACT_THRESHOLD = 20.0;
  static const int COOLDOWN_SECONDS = 60;

  bool get isMonitoring => _isMonitoring;

  void startMonitoring() {
    if (_isMonitoring) return;

    _isMonitoring = true;
    _accelerometerSubscription = accelerometerEvents.listen(
      _onAccelerometerEvent,
      onError: (error) {
        print('Accelerometer error: $error');
      },
    );
  }

  void stopMonitoring() {
    _isMonitoring = false;
    _accelerometerSubscription?.cancel();
    _accelerometerSubscription = null;
  }

  void _onAccelerometerEvent(AccelerometerEvent event) async {
    if (_accidentDetected) return;

    // Calculate total acceleration magnitude
    double magnitude = _calculateMagnitude(event.x, event.y, event.z);

    // Check if impact exceeds threshold
    if (magnitude > HIGH_IMPACT_THRESHOLD) {
      await _handleAccidentDetection();
    }
  }

  double _calculateMagnitude(double x, double y, double z) {
    return (x * x + y * y + z * z).abs();
  }

  Future<void> _handleAccidentDetection() async {
    // Check cooldown period
    if (_lastAlertTime != null) {
      final secondsSinceLastAlert = DateTime.now().difference(_lastAlertTime!).inSeconds;
      if (secondsSinceLastAlert < COOLDOWN_SECONDS) {
        return;
      }
    }

    _accidentDetected = true;
    _lastAlertTime = DateTime.now();

    // Get emergency number from preferences
    final prefs = await SharedPreferences.getInstance();
    final emergencyNumber = prefs.getString('emergency_number');

    if (emergencyNumber != null && emergencyNumber.isNotEmpty) {
      // Send emergency SMS with location
      bool sent = await SMSService.sendQuickEmergencySMS(emergencyNumber);

      if (sent) {
        print('Emergency SMS sent successfully to $emergencyNumber');
      } else {
        print('Failed to send emergency SMS');
      }
    }

    // Reset detection flag after cooldown
    Future.delayed(Duration(seconds: COOLDOWN_SECONDS), () {
      _accidentDetected = false;
    });
  }

  Future<void> testAccidentDetection() async {
    await _handleAccidentDetection();
  }

  void dispose() {
    stopMonitoring();
  }
}