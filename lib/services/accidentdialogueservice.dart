// lib/services/accident_dialog_service.dart - NEW FILE
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/sos_screen.dart';
import 'sms_service.dart';

class AccidentDialogService {
  static final AccidentDialogService _instance = AccidentDialogService._internal();
  factory AccidentDialogService() => _instance;
  AccidentDialogService._internal();

  static const int ALARM_DURATION = 30;

  BuildContext? _currentContext;
  bool _isDialogShowing = false;
  bool _isAlarmPlaying = false;
  Timer? _countdownTimer;
  int _remainingSeconds = ALARM_DURATION;

  // Store the current context from the app
  void setContext(BuildContext context) {
    _currentContext = context;
  }

  // Show accident dialog from anywhere
  Future<void> showAccidentDialog() async {
    if (_isDialogShowing || _currentContext == null) {
      print('⚠️ Dialog already showing or context not available');
      return;
    }

    if (!_currentContext!.mounted) {
      print('⚠️ Context not mounted');
      return;
    }

    _isDialogShowing = true;
    _remainingSeconds = ALARM_DURATION;

    // Start alarm
    await _startAlarm();

    // Show dialog
    showDialog(
      context: _currentContext!,
      barrierDismissible: false,
      builder: (dialogContext) => _AccidentAlertDialog(
        onCancel: () async {
          await _handleCancel(dialogContext);
        },
        onSendNow: () async {
          await _handleSendNow(dialogContext);
        },
        getRemainingSeconds: () => _remainingSeconds,
      ),
    );

    // Start countdown
    _startCountdown();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      _remainingSeconds--;

      if (_remainingSeconds <= 0) {
        timer.cancel();
        await _handleTimeout();
      }
    });
  }

  Future<void> _startAlarm() async {
    _isAlarmPlaying = true;

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
    _isAlarmPlaying = false;

    try {
      await FlutterRingtonePlayer().stop();
      print('⏹️ Alarm stopped');
    } catch (e) {
      print('❌ Stop alarm error: $e');
    }
  }

  Future<void> _handleCancel(BuildContext dialogContext) async {
    _countdownTimer?.cancel();
    await _stopAlarm();

    if (Navigator.canPop(dialogContext)) {
      Navigator.of(dialogContext).pop();
    }

    _isDialogShowing = false;
    print('✅ User cancelled - I\'m safe');
  }

  Future<void> _handleSendNow(BuildContext dialogContext) async {
    _countdownTimer?.cancel();
    await _stopAlarm();

    if (Navigator.canPop(dialogContext)) {
      Navigator.of(dialogContext).pop();
    }

    await _sendEmergencySMS();

    // Navigate to SOS screen
    if (_currentContext != null && _currentContext!.mounted) {
      Navigator.of(_currentContext!).push(
        MaterialPageRoute(builder: (_) => const SosScreen()),
      );
    }

    _isDialogShowing = false;
    print('✅ SMS sent - navigating to SOS screen');
  }

  Future<void> _handleTimeout() async {
    await _stopAlarm();

    // Close dialog
    if (_currentContext != null && _currentContext!.mounted) {
      Navigator.of(_currentContext!).pop();
    }

    await _sendEmergencySMS();

    // Navigate to SOS screen
    if (_currentContext != null && _currentContext!.mounted) {
      Navigator.of(_currentContext!).push(
        MaterialPageRoute(builder: (_) => const SosScreen()),
      );
    }

    _isDialogShowing = false;
    print('⏱️ Countdown finished - SMS sent automatically');
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

          await SMSService.sendEmergencySMS(phoneNumber);
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      print('✅ All emergency SMS sent');
    } catch (e) {
      print('❌ Error sending emergency SMS: $e');
    }
  }

  void dispose() {
    _countdownTimer?.cancel();
    _stopAlarm();
    _isDialogShowing = false;
  }
}

// Private dialog widget
class _AccidentAlertDialog extends StatefulWidget {
  final VoidCallback onCancel;
  final VoidCallback onSendNow;
  final int Function() getRemainingSeconds;

  const _AccidentAlertDialog({
    required this.onCancel,
    required this.onSendNow,
    required this.getRemainingSeconds,
  });

  @override
  State<_AccidentAlertDialog> createState() => _AccidentAlertDialogState();
}

class _AccidentAlertDialogState extends State<_AccidentAlertDialog> {
  late Timer _uiUpdateTimer;

  @override
  void initState() {
    super.initState();
    // Update UI every 100ms for smooth countdown
    _uiUpdateTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _uiUpdateTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remainingSeconds = widget.getRemainingSeconds();

    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 36),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                '🚨 ACCIDENT DETECTED!',
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Emergency contacts will be notified in:',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.red, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.3),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  '$remainingSeconds',
                  style: TextStyle(
                    fontSize: 56,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade700,
                    height: 1,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'seconds',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.volume_up, color: Colors.orange.shade700, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Alarm is ringing',
                    style: TextStyle(
                      color: Colors.orange.shade900,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: widget.onCancel,
                    icon: const Icon(Icons.check_circle, size: 24),
                    label: const Text(
                      "I'M SAFE",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: widget.onSendNow,
                    icon: const Icon(Icons.emergency, size: 24),
                    label: const Text(
                      'SEND SOS NOW',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}