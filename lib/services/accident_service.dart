// accident_service.dart - UPDATED to trigger alarm from anywhere
import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'sms_service.dart';

class AccidentDetectionService {
  static final AccidentDetectionService _instance = AccidentDetectionService._internal();
  factory AccidentDetectionService() => _instance;
  AccidentDetectionService._internal();

  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;

  bool _isMonitoring = false;
  bool _accidentDetected = false;
  bool _isAlarmPlaying = false;
  DateTime? _lastAlertTime;

  // Sensor data
  double _accelerateX = 0.0, _accelerateY = 0.0, _accelerateZ = 0.0;
  double _gyroscopeX = 0.0, _gyroscopeY = 0.0, _gyroscopeZ = 0.0;

  // Thresholds for accident detection (TEST MODE)
  static const double HIGH_ACCELERATION_THRESHOLD = 20.0;
  static const double MEDIUM_ACCELERATION_THRESHOLD = 15.0;
  static const double GYROSCOPE_THRESHOLD = 3.0;
  static const int REQUIRED_SAMPLES = 2;
  static const int COOLDOWN_SECONDS = 60;
  static const int ALARM_DURATION = 30;

  // Smoothing
  final List<double> _recentAccelerations = [];
  static const int SMOOTH_WINDOW = 5;
  int _highAccelerationCount = 0;

  bool get isMonitoring => _isMonitoring;

  void startMonitoring() {
    if (_isMonitoring) return;

    _isMonitoring = true;
    print('🟢 Accident detection service STARTED');

    _accelerometerSubscription = accelerometerEvents.listen(
      _onAccelerometerEvent,
      onError: (error) {
        print('Accelerometer error: $error');
      },
    );

    _gyroscopeSubscription = gyroscopeEvents.listen(
      _onGyroscopeEvent,
      onError: (error) {
        print('Gyroscope error: $error');
      },
    );
  }

  void stopMonitoring() {
    _isMonitoring = false;
    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();
    _accelerometerSubscription = null;
    _gyroscopeSubscription = null;
    print('🔴 Accident detection service STOPPED');
  }

  void _onAccelerometerEvent(AccelerometerEvent event) {
    _accelerateX = event.x;
    _accelerateY = event.y;
    _accelerateZ = event.z;

    if (!_isAlarmPlaying) {
      _checkForAccident();
    }
  }

  void _onGyroscopeEvent(GyroscopeEvent event) {
    _gyroscopeX = event.x;
    _gyroscopeY = event.y;
    _gyroscopeZ = event.z;
  }

  void _checkForAccident() {
    if (_accidentDetected) return;

    double accelerationMagnitude = sqrt(
        _accelerateX * _accelerateX +
            _accelerateY * _accelerateY +
            _accelerateZ * _accelerateZ
    );

    double gyroscopeMagnitude = sqrt(
        _gyroscopeX * _gyroscopeX +
            _gyroscopeY * _gyroscopeY +
            _gyroscopeZ * _gyroscopeZ
    );

    // Smooth readings
    _recentAccelerations.add(accelerationMagnitude);
    if (_recentAccelerations.length > SMOOTH_WINDOW) {
      _recentAccelerations.removeAt(0);
    }

    double avgAccel = _recentAccelerations.reduce((a, b) => a + b) /
        _recentAccelerations.length;

    // Ignore normal movement
    if (avgAccel < 10.0) return;
    if (gyroscopeMagnitude < 0.3) return;

    // Track sustained impact
    if (avgAccel > MEDIUM_ACCELERATION_THRESHOLD) {
      _highAccelerationCount++;
    } else {
      _highAccelerationCount = 0;
    }

    // Check for accident
    bool highImpact = avgAccel > HIGH_ACCELERATION_THRESHOLD &&
        _highAccelerationCount >= REQUIRED_SAMPLES;
    bool rollover = gyroscopeMagnitude > GYROSCOPE_THRESHOLD &&
        _highAccelerationCount >= REQUIRED_SAMPLES;

    if (highImpact || rollover) {
      print('🚨 ACCIDENT DETECTED! Triggering alarm...');
      _handleAccidentDetection();
    }
  }

  Future<void> _handleAccidentDetection() async {
    // Check cooldown period
    if (_lastAlertTime != null) {
      final secondsSinceLastAlert = DateTime.now().difference(_lastAlertTime!).inSeconds;
      if (secondsSinceLastAlert < COOLDOWN_SECONDS) {
        print('⏸️ Cooldown active. Ignoring detection.');
        return;
      }
    }

    _accidentDetected = true;
    _isAlarmPlaying = true;
    _lastAlertTime = DateTime.now();
    _highAccelerationCount = 0;

    // Start alarm
    await _startAlarm();

    // Wait for countdown
    int remainingSeconds = ALARM_DURATION;
    while (remainingSeconds > 0 && _isAlarmPlaying) {
      await Future.delayed(const Duration(seconds: 1));
      remainingSeconds--;
      print('⏱️ Countdown: $remainingSeconds seconds');
    }

    // If alarm still playing after countdown, send SMS
    if (_isAlarmPlaying) {
      print('📱 Countdown finished. Sending emergency SMS...');
      await _sendEmergencySMS();
      await _stopAlarm();
    }

    // Reset
    _accidentDetected = false;
    _isAlarmPlaying = false;
  }

  Future<void> _startAlarm() async {
    try {
      await FlutterRingtonePlayer().playAlarm(
        looping: true,
        volume: 1.0,
        asAlarm: true,
      );
      print('✅ Alarm started');
    } catch (e) {
      print('❌ Alarm error: $e');
    }
  }

  Future<void> _stopAlarm() async {
    try {
      await FlutterRingtonePlayer().stop();
      print('⏹️ Alarm stopped');
    } catch (e) {
      print('❌ Stop alarm error: $e');
    }
  }

  void cancelAlarm() {
    _isAlarmPlaying = false;
    _accidentDetected = false;
    _stopAlarm();
    print('✅ Alarm cancelled by user');
  }

  Future<void> _sendEmergencySMS() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final contactsJson = prefs.getStringList('emergency_contacts') ?? [];

      if (contactsJson.isEmpty) {
        print('⚠️ No emergency contacts found');
        return;
      }

      print('📱 Sending SMS to ${contactsJson.length} contacts...');

      for (String contactJson in contactsJson) {
        final parts = contactJson.split('|');
        if (parts.length >= 2) {
          final name = parts[0];
          final phoneNumber = parts[1];
          print('Sending to $name ($phoneNumber)...');

          bool sent = await SMSService.sendEmergencySMS(phoneNumber, message: "");

          if (sent) {
            print('✅ SMS sent to $name');
          } else {
            print('❌ Failed to send SMS to $name');
          }

          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      print('✅ All emergency SMS sent');
    } catch (e) {
      print('❌ Error sending emergency SMS: $e');
    }
  }

  Future<void> testAccidentDetection() async {
    print('🧪 Manual test triggered');
    await _handleAccidentDetection();
  }

  void dispose() {
    stopMonitoring();
    _stopAlarm();
  }
}