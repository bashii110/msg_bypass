import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:msg_bypas/screens/settings_scrren.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:noise_meter/noise_meter.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import '../services/sms_service.dart';

import 'emergencycontactscreen.dart';
import 'sos_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _isMonitoring = false;
  bool _isLoading = false;
  bool _isAccidentDetected = false;
  bool _isAlarmPlaying = false;

  double _accelerateX = 0.0, _accelerateY = 0.0, _accelerateZ = 0.0;
  double _gyroscopeX = 0.0, _gyroscopeY = 0.0, _gyroscopeZ = 0.0;
  double _latestDB = 0.0;

  late NoiseMeter _noiseMeter;
  StreamSubscription<NoiseReading>? _noiseSubscription;
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;

  int _highAccelerationCount = 0;
  int _highNoiseCount = 0;
  final List<double> _recentAccelerations = [];

  static const double HIGH_ACCELERATION_THRESHOLD = 20.0;
  static const double MEDIUM_ACCELERATION_THRESHOLD = 15.0;
  static const double HIGH_NOISE_THRESHOLD = 75.0;
  static const double MEDIUM_NOISE_THRESHOLD = 70.0;
  static const double GYROSCOPE_THRESHOLD = 3.0;
  static const int REQUIRED_SAMPLES = 2;
  static const int SMOOTH_WINDOW = 5;
  static const int ALARM_DURATION = 30;

  // Platform channel for native alarm service
  static const platform = MethodChannel('com.buxhiisd.msg_bypas/alarm');
  static const EventChannel userSafeChannel = EventChannel('com.buxhiisd.msg_bypas/user_safe');

  // Countdown tracking using absolute time (survives background!)
  DateTime? _countdownEndTime;
  Timer? _uiUpdateTimer;
  StreamSubscription? _userSafeSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _noiseMeter = NoiseMeter();
    _loadSettings();
    _setupUserSafeBroadcastReceiver();
  }

  void _setupUserSafeBroadcastReceiver() {
    // Listen for "I'm Safe" button pressed from notification
    _userSafeSubscription = userSafeChannel.receiveBroadcastStream().listen((event) {
      print("✅ User pressed 'I'm Safe' from notification");
      _handleUserSafe();
    }, onError: (error) {
      print("❌ UserSafe event error: $error");
    });
  }


  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopMonitoring();
    _uiUpdateTimer?.cancel();
    _userSafeSubscription?.cancel();
    FlutterRingtonePlayer().stop();
    _stopNativeAlarmService();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      // When app comes back to foreground, check status
      _checkCountdownStatus();
      _checkUserSafeStatus();
    }
  }

  void _checkCountdownStatus() {
    if (_countdownEndTime != null) {
      final now = DateTime.now();
      if (now.isAfter(_countdownEndTime!)) {
        print("🚨 Countdown completed while in background!");
        _onCountdownComplete();
      }
    }
  }

  Future<void> _checkUserSafeStatus() async {
    // Check via method channel if user pressed "I'm Safe"
    try {
      final result = await platform.invokeMethod('checkUserSafe');
      if (result == true) {
        print("✅ User marked safe from notification");
        _handleUserSafe();
      }
    } catch (e) {
      // Method not implemented yet, ignore
    }
  }

  int _getRemainingSeconds() {
    if (_countdownEndTime == null) return ALARM_DURATION;

    final now = DateTime.now();
    final remaining = _countdownEndTime!.difference(now).inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isMonitoring = prefs.getBool('monitoring_enabled') ?? false;
    });
    if (_isMonitoring) _startMonitoring();
  }

  void _startMonitoring() {
    if (_isMonitoring) {
      try {
        _noiseSubscription = _noiseMeter.noise.listen((reading) {
          if (mounted) {
            _latestDB = reading.meanDecibel;
            if (!_isAlarmPlaying) _checkForAccident();
          }
        });
      } catch (e) {
        print('Noise error: $e');
      }

      _accelerometerSubscription = accelerometerEvents.listen((event) {
        _accelerateX = event.x;
        _accelerateY = event.y;
        _accelerateZ = event.z;
        if (!_isAlarmPlaying) _checkForAccident();
      });

      _gyroscopeSubscription = gyroscopeEvents.listen((event) {
        _gyroscopeX = event.x;
        _gyroscopeY = event.y;
        _gyroscopeZ = event.z;
      });
    }
  }

  void _stopMonitoring() {
    _noiseSubscription?.cancel();
    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();
  }

  void _checkForAccident() {
    if (_isAccidentDetected || !_isMonitoring) return;

    double accelerationMagnitude = sqrt(_accelerateX * _accelerateX +
        _accelerateY * _accelerateY +
        _accelerateZ * _accelerateZ);

    double gyroscopeMagnitude = sqrt(_gyroscopeX * _gyroscopeX +
        _gyroscopeY * _gyroscopeY +
        _gyroscopeZ * _gyroscopeZ);

    _recentAccelerations.add(accelerationMagnitude);
    if (_recentAccelerations.length > SMOOTH_WINDOW) {
      _recentAccelerations.removeAt(0);
    }

    if (_recentAccelerations.isEmpty) return;

    double avgAccel = _recentAccelerations.reduce((a, b) => a + b) / _recentAccelerations.length;

    if (avgAccel < 10.0) return;
    if (gyroscopeMagnitude < 0.3) return;

    if (avgAccel > MEDIUM_ACCELERATION_THRESHOLD) {
      _highAccelerationCount++;
    } else {
      _highAccelerationCount = 0;
    }

    if (_latestDB > MEDIUM_NOISE_THRESHOLD) {
      _highNoiseCount++;
    } else {
      _highNoiseCount = 0;
    }

    bool highImpact = avgAccel > HIGH_ACCELERATION_THRESHOLD && _highAccelerationCount >= REQUIRED_SAMPLES;
    bool impactWithNoise = _highAccelerationCount >= REQUIRED_SAMPLES && _highNoiseCount >= REQUIRED_SAMPLES;
    bool noiseWithImpact = _latestDB > HIGH_NOISE_THRESHOLD && avgAccel > MEDIUM_ACCELERATION_THRESHOLD;
    bool rollover = gyroscopeMagnitude > GYROSCOPE_THRESHOLD && _highAccelerationCount >= REQUIRED_SAMPLES;

    if (highImpact || impactWithNoise || noiseWithImpact || rollover) {
      _triggerAccident();
    }
  }

  void _triggerAccident() {
    _isAccidentDetected = true;
    _highAccelerationCount = 0;
    _highNoiseCount = 0;
    _startAccidentCountdown();
  }

  Future<void> _startAccidentCountdown() async {
    print("🚨 Starting accident countdown...");

    // Set absolute end time (this survives background!)
    _countdownEndTime = DateTime.now().add(Duration(seconds: ALARM_DURATION));

    // Start alarm sound
    await _startAlarm();

    // Turn screen on via native
    try {
      await platform.invokeMethod('turnScreenOn');
      print("✅ Screen turned on");
    } catch (e) {
      print('Failed to turn screen on: $e');
    }

    // Start native foreground service
    try {
      await platform.invokeMethod('startAlarmService', {
        'duration': ALARM_DURATION,
      });
      print("✅ Alarm service started in background");
    } catch (e) {
      print('❌ Failed to start alarm service: $e');
    }

    // Start UI update timer - check time continuously
    _uiUpdateTimer?.cancel();
    _uiUpdateTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      final remaining = _getRemainingSeconds();

      if (mounted) {
        setState(() {}); // Update UI
      }

      print("⏱️ Remaining: $remaining seconds");

      if (remaining <= 0) {
        timer.cancel();
        print("⏰ Countdown complete!");
        _onCountdownComplete();
      }
    });

    // Show dialog
    if (mounted) {
      _showAccidentDialog();
    }
  }

  Future<void> _onCountdownComplete() async {
    if (!_isAccidentDetected) return; // Prevent double-trigger

    print("✅ Countdown complete - sending emergency SMS");

    _uiUpdateTimer?.cancel();
    _countdownEndTime = null;

    await _stopAlarm();
    await _stopNativeAlarmService();

    // SEND SMS!
    await _sendEmergencySMS();

    if (mounted) {
      // Close dialog if still open
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }

      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SosScreen()),
      );
      setState(() => _isAccidentDetected = false);
    }
  }

  void _handleUserSafe() {
    print("✅ User is safe - stopping alarm");

    _uiUpdateTimer?.cancel();
    _countdownEndTime = null;

    _stopAlarm();
    _stopNativeAlarmService();

    if (mounted) {
      // Close dialog if still open
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }

      setState(() => _isAccidentDetected = false);

      _showSnackBar('✅ Alarm cancelled - Stay safe!', Colors.green);
    }
  }

  Future<void> _stopNativeAlarmService() async {
    try {
      await platform.invokeMethod('stopAlarmService');
      print("✅ Alarm service stopped");
    } catch (e) {
      print('Failed to stop alarm service: $e');
    }
  }

  Future<void> _startAlarm() async {
    _isAlarmPlaying = true;
    try {
      await FlutterRingtonePlayer().playAlarm(looping: true, volume: 1.0, asAlarm: true);
      HapticFeedback.heavyImpact();
      print("🔊 Alarm started");
    } catch (e) {
      print('Alarm error: $e');
    }
  }

  Future<void> _stopAlarm() async {
    _isAlarmPlaying = false;
    try {
      await FlutterRingtonePlayer().stop();
      print("🔇 Alarm stopped");
    } catch (e) {
      print('Stop error: $e');
    }
  }

  void _showAccidentDialog() async {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: StatefulBuilder(
          builder: (_, setDialogState) {
            // Update dialog continuously
            Timer.periodic(const Duration(milliseconds: 300), (timer) {
              if (!mounted || !_isAccidentDetected) {
                timer.cancel();
                return;
              }
              if (mounted) {
                setDialogState(() {});
              }
            });

            final remainingSeconds = _getRemainingSeconds();

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 36),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('🚨 ACCIDENT!', style: TextStyle(color: Colors.red, fontSize: 22, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Emergency contacts\nwill be notified in:', textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 24),
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.red, width: 4),
                      boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.3), blurRadius: 20, spreadRadius: 5)],
                    ),
                    child: Center(
                      child: Text('$remainingSeconds', style: TextStyle(fontSize: 56, fontWeight: FontWeight.bold, color: Colors.red.shade700)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('seconds', style: TextStyle(fontSize: 16, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                ],
              ),
              actions: [
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          print("✅ User clicked I'M SAFE");
                          _handleUserSafe();
                        },

                        icon: const Icon(Icons.check_circle, size: 24),
                        label: const Text("I'M SAFE", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          print("🆘 User clicked SEND SOS NOW");
                          _uiUpdateTimer?.cancel();
                          _countdownEndTime = null;
                          await _stopNativeAlarmService();
                          await _stopAlarm();
                          Navigator.of(dialogContext).pop();
                          await _sendEmergencySMS();
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const SosScreen()));
                          setState(() => _isAccidentDetected = false);
                        },
                        icon: const Icon(Icons.emergency, size: 24),
                        label: const Text('SEND SOS NOW', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _sendEmergencySMS() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final contactsJson = prefs.getStringList('emergency_contacts') ?? [];

      if (contactsJson.isEmpty) {
        print("⚠️ No emergency contacts found");
        return;
      }

      print("📤 Sending SMS to ${contactsJson.length} contacts");

      for (String contactJson in contactsJson) {
        final parts = contactJson.split('|');
        if (parts.length >= 2) {
          await SMSService.sendEmergencySMS(parts[1], message: '');
          print("✅ SMS sent to ${parts[0]} (${parts[1]})");
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      print("✅ All SMS sent successfully!");
    } catch (e) {
      print('❌ SMS error: $e');
    }
  }

  Future<void> _toggleMonitoring() async {
    setState(() => _isMonitoring = !_isMonitoring);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('monitoring_enabled', _isMonitoring);

    if (_isMonitoring) {
      _startMonitoring();
      _showSnackBar('✅ Accident detection started', Colors.green);
    } else {
      _stopMonitoring();
      _showSnackBar('⏸️ Accident detection stopped', Colors.orange);
    }
  }

  Future<void> _sendManualAlert() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send Emergency Alert?'),
        content: const Text('Send emergency SMS with location to all contacts?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Send'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        await _sendEmergencySMS();
        setState(() => _isLoading = false);
        if (!mounted) return;
        Navigator.push(context, MaterialPageRoute(builder: (_) => const SosScreen()));
      } catch (e) {
        _showSnackBar('Error: $e', Colors.red);
        setState(() => _isLoading = false);
      }
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color, duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rescue Me'),
        centerTitle: true,
        backgroundColor: Colors.blueAccent,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
              _loadSettings();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStatusCard(),
            const SizedBox(height: 16),
            _buildEmergencyContactCard(),
            const SizedBox(height: 16),
            _buildTestModeCard(),
            const SizedBox(height: 16),
            _buildInfoCard(),
            const SizedBox(height: 80),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isLoading ? null : _sendManualAlert,
        backgroundColor: Colors.red,
        icon: _isLoading
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.emergency),
        label: const Text('SEND SOS'),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      color: Colors.blueAccent,
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(_isMonitoring ? Icons.sensors : Icons.sensors_off, size: 64, color: _isMonitoring ? Colors.green : Colors.grey),
            const SizedBox(height: 16),
            Text(_isMonitoring ? 'Monitoring Active' : 'Monitoring Inactive',
                style: const TextStyle(color: Colors.white ,fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(_isMonitoring ? 'Accident detection running' : 'Tap below to start',
                style:const TextStyle(color: Colors.white, fontSize: 14)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _toggleMonitoring,
                icon: Icon(_isMonitoring ? Icons.stop : Icons.play_arrow),
                label: Text(_isMonitoring ? 'Stop Monitoring' : 'Start Monitoring'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: _isMonitoring ? Colors.redAccent : Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmergencyContactCard() {
    return FutureBuilder<int>(
      future: _getContactCount(),
      builder: (context, snapshot) {
        final contactCount = snapshot.data ?? 0;
        return Card(
          elevation: 2,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: contactCount > 0 ? Colors.green : Colors.orange,
              child: Text('$contactCount', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            title: Text(contactCount > 0 ? '$contactCount Contact${contactCount > 1 ? 's' : ''}' : 'No Contacts',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(contactCount > 0 ? 'Will receive alerts' : 'Tap to add'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const EmergencyContactsScreen()));
              setState(() {});
            },
          ),
        );
      },
    );
  }

  Future<int> _getContactCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList('emergency_contacts') ?? []).length;
    } catch (e) {
      return 0;
    }
  }

  Widget _buildTestModeCard() {
    return Card(
      elevation: 3,
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.orange),
                const SizedBox(width: 8),
                const Text("Detection Thresholds (TEST MODE):",
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
              ],
            ),
            const SizedBox(height: 6),
            Text("• Severe impact: > ${HIGH_ACCELERATION_THRESHOLD.toStringAsFixed(1)} m/s² (${REQUIRED_SAMPLES} readings)"),
            Text("• Loud noise: > ${HIGH_NOISE_THRESHOLD.toStringAsFixed(1)} dB"),
            Text("• Rollover: > ${GYROSCOPE_THRESHOLD.toStringAsFixed(1)} rad/s rotation"),
            const Text("• Combined sustained impact + noise triggers detection"),
            const SizedBox(height: 10),
            const Text("✅ Time-based countdown - works in background!",
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 12)),
            const SizedBox(height: 4),
            const Text("TIP: Shake your phone vigorously or make a loud noise to test!",
                style: TextStyle(fontStyle: FontStyle.italic, color: Colors.orange, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      elevation: 2,
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text('How It Works', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoItem('• Monitors sensors for sudden impacts'),
            _buildInfoItem('• Automatically detects accidents'),
            _buildInfoItem('• ✅ Works in background & screen off'),
            _buildInfoItem('• Sends SMS with GPS location'),
            _buildInfoItem('• Includes Google Maps link'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(text, style: TextStyle(color: Colors.blue.shade900, fontSize: 13)),
    );
  }
}