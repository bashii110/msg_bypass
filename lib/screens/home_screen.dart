import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:msg_bypas/screens/settings_scrren.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:noise_meter/noise_meter.dart';
import 'package:audioplayers/audioplayers.dart';
import '../services/sms_service.dart';
import '../services/call_service.dart';

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
  bool _isBatteryOptimized = true;

  double _accelerateX = 0.0, _accelerateY = 0.0, _accelerateZ = 0.0;
  double _gyroscopeX = 0.0, _gyroscopeY = 0.0, _gyroscopeZ = 0.0;
  double _latestDB = 0.0;

  late NoiseMeter _noiseMeter;
  late AudioPlayer _audioPlayer;

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

  // Platform channels
  static const platform = MethodChannel('com.buxhiisd.msg_bypas/alarm');
  static const serviceChannel = MethodChannel('com.buxhiisd.msg_bypas/service');

  // Countdown tracking
  DateTime? _countdownEndTime;
  Timer? _uiUpdateTimer;
  Timer? _userSafeCheckTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _noiseMeter = NoiseMeter();
    _audioPlayer = AudioPlayer();
    _loadSettings();
    _checkBatteryOptimization();

    // Listen for background accident detection
    platform.setMethodCallHandler(_handleMethodCall);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onAccidentDetectedBackground') {
      print('🚨 Accident detected from background service!');
      if (mounted && !_isAccidentDetected) {
        _triggerAccident();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopForegroundMonitoring();
    _uiUpdateTimer?.cancel();
    _userSafeCheckTimer?.cancel();
    _audioPlayer.dispose();
    _stopNativeAlarmService();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      print("🔄 App resumed - checking status");
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
    try {
      final result = await platform.invokeMethod('checkUserSafe');
      if (result == true) {
        print("✅ User marked safe from notification");
        _handleUserSafe();
      }
    } catch (e) {
      print("Error checking user safe status: $e");
    }
  }

  Future<void> _checkBatteryOptimization() async {
    try {
      final result = await serviceChannel.invokeMethod('isBatteryOptimized');
      setState(() {
        _isBatteryOptimized = result == true;
      });
    } catch (e) {
      print('Error checking battery optimization: $e');
    }
  }

  Future<void> _requestIgnoreBatteryOptimization() async {
    try {
      await serviceChannel.invokeMethod('requestIgnoreBatteryOptimization');
      await Future.delayed(const Duration(seconds: 2));
      await _checkBatteryOptimization();
    } catch (e) {
      print('Error requesting battery optimization: $e');
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
    if (_isMonitoring) {
      _startBackgroundService();
      _startForegroundMonitoring(); // Also monitor in foreground for immediate response
    }
  }

  // START/STOP BACKGROUND SERVICE
  Future<void> _startBackgroundService() async {
    try {
      await serviceChannel.invokeMethod('startMonitoringService');
      print('✅ Background monitoring service started');
    } catch (e) {
      print('❌ Failed to start background service: $e');
    }
  }

  Future<void> _stopBackgroundService() async {
    try {
      await serviceChannel.invokeMethod('stopMonitoringService');
      print('⏸️ Background monitoring service stopped');
    } catch (e) {
      print('Failed to stop background service: $e');
    }
  }

  // FOREGROUND MONITORING (when app is open)
  void _startForegroundMonitoring() {
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

  void _stopForegroundMonitoring() {
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

    _countdownEndTime = DateTime.now().add(Duration(seconds: ALARM_DURATION));

    await _startAlarm();

    try {
      await platform.invokeMethod('turnScreenOn');
      print("✅ Screen turned on");
    } catch (e) {
      print('Failed to turn screen on: $e');
    }

    try {
      await platform.invokeMethod('startAlarmService', {
        'duration': ALARM_DURATION,
      });
      print("✅ Alarm service started in background");
    } catch (e) {
      print('❌ Failed to start alarm service: $e');
    }

    _startUserSafePolling();

    _uiUpdateTimer?.cancel();
    _uiUpdateTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      final remaining = _getRemainingSeconds();

      if (mounted) {
        setState(() {});
      }

      print("⏱️ Remaining: $remaining seconds");

      if (remaining <= 0) {
        timer.cancel();
        print("⏰ Countdown complete!");
        _onCountdownComplete();
      }
    });

    if (mounted) {
      _showAccidentDialog();
    }
  }

  void _startUserSafePolling() {
    _userSafeCheckTimer?.cancel();
    _userSafeCheckTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!_isAccidentDetected) {
        timer.cancel();
        return;
      }
      _checkUserSafeStatus();
    });
  }

  Future<void> _onCountdownComplete() async {
    if (!_isAccidentDetected) return;

    print("✅ Countdown complete - sending emergency SMS");

    _uiUpdateTimer?.cancel();
    _userSafeCheckTimer?.cancel();
    _countdownEndTime = null;

    await _stopAlarm();
    await _stopNativeAlarmService();

    await _sendEmergencySMS();

    if (mounted) {
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
    print("✅ User is safe - stopping alarm IMMEDIATELY");

    _uiUpdateTimer?.cancel();
    _userSafeCheckTimer?.cancel();
    _countdownEndTime = null;

    _stopAlarm();
    _stopNativeAlarmService();

    if (mounted) {
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
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.setVolume(1.0);

      await _audioPlayer.setAudioContext(
        const AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: [AVAudioSessionOptions.mixWithOthers],
          ),
          android: AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: true,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.alarm,
            audioFocus: AndroidAudioFocus.gain,
          ),
        ),
      );

      await _audioPlayer.play(AssetSource('images/Alert_alarm.wav'));
      HapticFeedback.heavyImpact();
      print("✅ Custom alarm started successfully");
    } catch (e) {
      print('❌ Alarm error: $e');
    }
  }

  Future<void> _stopAlarm() async {
    _isAlarmPlaying = false;
    try {
      await _audioPlayer.stop();
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
                          print("✅ User clicked I'M SAFE from dialog");
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
                          _userSafeCheckTimer?.cancel();
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

      List<String> phoneNumbers = [];

      for (String contactJson in contactsJson) {
        final parts = contactJson.split('|');
        if (parts.length >= 2) {
          await SMSService.sendEmergencySMS(parts[1], message: '');
          print("✅ SMS sent to ${parts[0]} (${parts[1]})");
          phoneNumbers.add(parts[1]);
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      print("✅ All SMS sent successfully!");

      if (phoneNumbers.isNotEmpty) {
        print("📞 Starting emergency calls...");

        final hasPermission = await CallService.hasCallPermission();
        if (!hasPermission) {
          print("⚠️ Requesting call permission...");
          await CallService.requestCallPermission();
          await Future.delayed(const Duration(seconds: 2));
        }

        await CallService.makeEmergencyCalls(
          phoneNumbers,
          delayBetweenCalls: const Duration(seconds: 30),
        );

        print("✅ All emergency calls initiated!");
      }
    } catch (e) {
      print('❌ SMS/Call error: $e');
    }
  }

  Future<void> _toggleMonitoring() async {
    setState(() => _isMonitoring = !_isMonitoring);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('monitoring_enabled', _isMonitoring);

    if (_isMonitoring) {
      await _startBackgroundService();
      _startForegroundMonitoring();
      _showSnackBar('✅ Accident detection started', Colors.green);
    } else {
      await _stopBackgroundService();
      _stopForegroundMonitoring();
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
        // actions: [
        //   IconButton(
        //     icon: const Icon(Icons.settings),
        //     onPressed: () async {
        //       await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
        //       _loadSettings();
        //     },
        //   ),
        // ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isBatteryOptimized) _buildBatteryWarningCard(),
            const SizedBox(height: 16),
            _buildStatusCard(),
            const SizedBox(height: 16),
            // _buildEmergencyContactCard(),
            // const SizedBox(height: 16),
            _buildTestModeCard(),
            const SizedBox(height: 16),
            _buildInfoCard(),
            const SizedBox(height: 80),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isLoading ? null : _sendManualAlert,
        backgroundColor: Colors.blue.shade700,
        icon: _isLoading
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.location_on, color: Colors.white,),
        label: const Text('SEND SOS',style: TextStyle(color: Colors.white),),
      ),
    );
  }

  Widget _buildBatteryWarningCard() {
    return Card(
      elevation: 4,
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.battery_alert, color: Colors.orange.shade700, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('⚠️ Battery Optimization Active',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('For reliable background detection on Vivo/Oppo/Xiaomi phones, disable battery optimization.',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _requestIgnoreBatteryOptimization,
                icon: const Icon(Icons.power_settings_new, size: 20),
                label: const Text('Disable Battery Optimization'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
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
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(_isMonitoring ? '✅ Background service running' : 'Tap below to start',
                style: const TextStyle(color: Colors.white, fontSize: 14)),
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

  // Widget _buildEmergencyContactCard() {
  //   return FutureBuilder<int>(
  //     future: _getContactCount(),
  //     builder: (context, snapshot) {
  //       final contactCount = snapshot.data ?? 0;
  //       return Card(
  //         elevation: 2,
  //         child: ListTile(
  //           leading: CircleAvatar(
  //             backgroundColor: contactCount > 0 ? Colors.green : Colors.orange,
  //             child: Text('$contactCount', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
  //           ),
  //           title: Text(contactCount > 0 ? '$contactCount Contact${contactCount > 1 ? 's' : ''}' : 'No Contacts',
  //               style: const TextStyle(fontWeight: FontWeight.bold)),
  //           subtitle: Text(contactCount > 0 ? 'Will receive alerts' : 'Tap to add'),
  //           trailing: const Icon(Icons.arrow_forward_ios),
  //           onTap: () async {
  //             await Navigator.push(context, MaterialPageRoute(builder: (_) => const EmergencyContactsScreen()));
  //             setState(() {});
  //           },
  //         ),
  //       );
  //     },
  //   );
  // }

  // Future<int> _getContactCount() async {
  //   try {
  //     final prefs = await SharedPreferences.getInstance();
  //     return (prefs.getStringList('emergency_contacts') ?? []).length;
  //   } catch (e) {
  //     return 0;
  //   }
  // }

  Widget _buildTestModeCard() {
    return Card(
      elevation: 3,
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                 Icon(Icons.info_outline, color: Colors.orange),
                 SizedBox(width: 8),
                 Text("Detection Thresholds:",
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
              ],
            ),
            const SizedBox(height: 6),
            Text("• Severe impact: > ${HIGH_ACCELERATION_THRESHOLD.toStringAsFixed(1)} m/s²"),
            Text("• Loud noise: > ${HIGH_NOISE_THRESHOLD.toStringAsFixed(1)} dB"),
            Text("• Rollover: > ${GYROSCOPE_THRESHOLD.toStringAsFixed(1)} rad/s"),
            const SizedBox(height: 10),
            const Text("✅ Background service keeps monitoring even when app is closed!",
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 12)),
            const SizedBox(height: 10),

            //Test Alarm sound

            // ElevatedButton.icon(
            //   onPressed: () async {
            //     print("🧪 Testing alarm sound...");
            //     await _startAlarm();
            //     await Future.delayed(const Duration(seconds: 3));
            //     await _stopAlarm();
            //   },
            //   icon: const Icon(Icons.volume_up, size: 20),
            //   label: const Text('TEST ALARM SOUND'),
            //   style: ElevatedButton.styleFrom(
            //     backgroundColor: Colors.blue,
            //     foregroundColor: Colors.white,
            //   ),
            // ),
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
            _buildInfoItem('• ✅ Works in background (even when app closed)'),
            _buildInfoItem('• ✅ Works when screen is off'),
            _buildInfoItem('• Automatically detects accidents'),
            _buildInfoItem('• Sends SMS with GPS location'),
            _buildInfoItem('• 📞 Calls emergency contacts'),
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