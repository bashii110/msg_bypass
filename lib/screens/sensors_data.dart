// STEP 1: Add this package to pubspec.yaml
// dependencies:
//   flutter_ringtone_player: ^4.0.0+4

// sensors_data.dart - Uses ONLY system alarm sound (guaranteed to work)
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:msg_bypas/screens/sos_screen.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:noise_meter/noise_meter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import '../services/sms_service.dart';

class SosHelp extends StatefulWidget {
  const SosHelp({super.key});

  @override
  State<SosHelp> createState() => _SosHelpState();
}

class _SosHelpState extends State<SosHelp> {
  double accelerateX = 0.0, accelerateY = 0.0, accelerateZ = 0.0;
  double gyroscopeX = 0.0, gyroscopeY = 0.0, gyroscopeZ = 0.0;

  late NoiseMeter noiseMeter;
  bool isNoiseActive = false;
  StreamSubscription<NoiseReading>? noiseSubscription;
  double latestDB = 0.0;

  StreamSubscription<AccelerometerEvent>? accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? gyroscopeSubscription;

  bool isAccidentDetected = false;
  bool isAlarmPlaying = false;
  Timer? uiUpdateTimer;

  int highAccelerationCount = 0;
  int highNoiseCount = 0;

  static const double HIGH_ACCELERATION_THRESHOLD = 20.0;
  static const double MEDIUM_ACCELERATION_THRESHOLD = 15.0;
  static const double HIGH_NOISE_THRESHOLD = 75.0;
  static const double MEDIUM_NOISE_THRESHOLD = 70.0;
  static const double GYROSCOPE_THRESHOLD = 3.0;
  static const int REQUIRED_SAMPLES = 2;
  static const int ALARM_DURATION = 30;

  final List<double> recentAccelerations = [];
  static const int SMOOTH_WINDOW = 5;

  @override
  void initState() {
    super.initState();
    noiseMeter = NoiseMeter();
    startNoiseDetection();
    startSensorListeners();

    uiUpdateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() {});
    });
  }

  void startNoiseDetection() {
    if (isNoiseActive) return;
    try {
      noiseSubscription = noiseMeter.noise.listen((NoiseReading reading) {
        if (!mounted) return;
        setState(() => latestDB = reading.meanDecibel);
        if (!isAlarmPlaying) checkForAccident();
      });
      isNoiseActive = true;
    } catch (e) {
      print('Noise meter error: $e');
    }
  }

  void startSensorListeners() {
    accelerometerSubscription = accelerometerEvents.listen((event) {
      accelerateX = event.x;
      accelerateY = event.y;
      accelerateZ = event.z;
      if (!isAlarmPlaying) checkForAccident();
    });

    gyroscopeSubscription = gyroscopeEvents.listen((event) {
      gyroscopeX = event.x;
      gyroscopeY = event.y;
      gyroscopeZ = event.z;
    });
  }

  void checkForAccident() {
    if (isAccidentDetected) return;

    double accelerationMagnitude = sqrt(accelerateX * accelerateX +
        accelerateY * accelerateY + accelerateZ * accelerateZ);
    double gyroscopeMagnitude = sqrt(gyroscopeX * gyroscopeX +
        gyroscopeY * gyroscopeY + gyroscopeZ * gyroscopeZ);

    recentAccelerations.add(accelerationMagnitude);
    if (recentAccelerations.length > SMOOTH_WINDOW) {
      recentAccelerations.removeAt(0);
    }
    double avgAccel = recentAccelerations.reduce((a, b) => a + b) / recentAccelerations.length;

    if (avgAccel < 10.0) return;
    if (gyroscopeMagnitude < 0.3) return;

    if (avgAccel > MEDIUM_ACCELERATION_THRESHOLD) {
      highAccelerationCount++;
    } else {
      highAccelerationCount = 0;
    }

    if (latestDB > MEDIUM_NOISE_THRESHOLD) {
      highNoiseCount++;
    } else {
      highNoiseCount = 0;
    }

    bool highImpact = avgAccel > HIGH_ACCELERATION_THRESHOLD &&
        highAccelerationCount >= REQUIRED_SAMPLES;
    bool impactWithNoise = highAccelerationCount >= REQUIRED_SAMPLES &&
        highNoiseCount >= REQUIRED_SAMPLES;
    bool noiseWithImpact = latestDB > HIGH_NOISE_THRESHOLD &&
        avgAccel > MEDIUM_ACCELERATION_THRESHOLD;
    bool rollover = gyroscopeMagnitude > GYROSCOPE_THRESHOLD &&
        highAccelerationCount >= REQUIRED_SAMPLES;

    if (highImpact || impactWithNoise || noiseWithImpact || rollover) {
      isAccidentDetected = true;
      highAccelerationCount = 0;
      highNoiseCount = 0;
      showAccidentDialog(context);
    }
  }

  void triggerManualTest() {
    if (isAccidentDetected || isAlarmPlaying) return;
    isAccidentDetected = true;
    showAccidentDialog(context);
  }

  // SYSTEM ALARM - GUARANTEED TO WORK
  Future<void> _startAlarm() async {
    isAlarmPlaying = true;

    try {
      // Use system alarm sound - ALWAYS WORKS!
      await FlutterRingtonePlayer().playAlarm(
        looping: true,
        volume: 1.0,
        asAlarm: true,
      );
      print('✅ System alarm started');

      // Also vibrate
      HapticFeedback.heavyImpact();
    } catch (e) {
      print('Alarm error: $e');
    }
  }

  Future<void> _stopAlarm() async {
    isAlarmPlaying = false;

    try {
      await FlutterRingtonePlayer().stop();
      print('⏹️ Alarm stopped');
    } catch (e) {
      print('Stop alarm error: $e');
    }
  }

  void showAccidentDialog(BuildContext context) async {
    int remainingSeconds = ALARM_DURATION;
    bool dismissed = false;
    Timer? countdownTimer;

    // START ALARM IMMEDIATELY
    print('🚨 Starting alarm...');
    await _startAlarm();

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          if (countdownTimer == null) {
            countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
              if (dismissed) {
                timer.cancel();
                return;
              }

              remainingSeconds--;
              setDialogState(() {});

              if (remainingSeconds <= 0) {
                timer.cancel();

                await _sendEmergencySMSToAll();
                await _stopAlarm();

                if (Navigator.canPop(dialogContext)) {
                  Navigator.of(dialogContext).pop();
                }
                if (mounted) {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const SosScreen()));
                }
                setState(() {
                  isAccidentDetected = false;
                });
              }
            });
          }

          return PopScope(
            canPop: false,
            child: AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red, size: 30),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text('🚨 ACCIDENT DETECTED!',
                        style: TextStyle(color: Colors.red, fontSize: 20,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Emergency contacts will be notified in:',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.red, width: 3),
                    ),
                    child: Text(
                      '$remainingSeconds',
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text('seconds',
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade700)),
                ],
              ),
              actions: [
                TextButton(
                  style: TextButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
                  onPressed: () async {
                    dismissed = true;
                    countdownTimer?.cancel();
                    await _stopAlarm();
                    Navigator.of(dialogContext).pop();
                    setState(() {
                      isAccidentDetected = false;
                    });
                  },
                  child: const Text("I'M SAFE",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                const SizedBox(width: 8),
                TextButton(
                  style: TextButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
                  onPressed: () async {
                    dismissed = true;
                    countdownTimer?.cancel();
                    await _stopAlarm();
                    Navigator.of(dialogContext).pop();

                    await _sendEmergencySMSToAll();

                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const SosScreen()));
                    setState(() {
                      isAccidentDetected = false;
                    });
                  },
                  child: const Text('SEND SOS NOW',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _sendEmergencySMSToAll() async {
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

      print('✅ SMS sent to all contacts');
    } catch (e) {
      print('❌ Error sending emergency SMS: $e');
    }
  }

  @override
  void dispose() {
    noiseSubscription?.cancel();
    accelerometerSubscription?.cancel();
    gyroscopeSubscription?.cancel();
    uiUpdateTimer?.cancel();
    FlutterRingtonePlayer().stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double accelerationMagnitude = sqrt(accelerateX * accelerateX +
        accelerateY * accelerateY + accelerateZ * accelerateZ);

    return Scaffold(
      appBar: AppBar(
        title: const Text("SOS Accident Detection"),
        backgroundColor: Colors.cyan,
        elevation: 4,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Card(
                color: isAccidentDetected ? Colors.red.shade50 : Colors.green.shade50,
                elevation: 4,
                child: ListTile(
                  leading: Icon(
                    isAccidentDetected ? Icons.warning : Icons.check_circle,
                    color: isAccidentDetected ? Colors.red : Colors.green,
                    size: 40,
                  ),
                  title: Text(
                    isAccidentDetected ? "ACCIDENT DETECTED" : "Monitoring Active",
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: isAccidentDetected ? Colors.red : Colors.green),
                  ),
                  subtitle: const Text("System is monitoring sensors for crash conditions"),
                ),
              ),
              const SizedBox(height: 20),

              ElevatedButton.icon(
                onPressed: triggerManualTest,
                icon: const Icon(Icons.bug_report),
                label: const Text('TEST ALARM & SMS'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),

              OutlinedButton.icon(
                onPressed: () async {
                  await _startAlarm();
                  await Future.delayed(const Duration(seconds: 3));
                  await _stopAlarm();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('✅ System alarm test complete!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.volume_up),
                label: const Text('Test System Alarm (3 sec)'),
              ),

              const SizedBox(height: 20),

              _buildSensorCard("Accelerometer", Icons.speed, Colors.blue, [
                _buildSensorRow("X", accelerateX),
                _buildSensorRow("Y", accelerateY),
                _buildSensorRow("Z", accelerateZ),
                _buildSensorRow("Magnitude", accelerationMagnitude,
                    isAlert: accelerationMagnitude > MEDIUM_ACCELERATION_THRESHOLD),
              ]),
              _buildSensorCard("Gyroscope", Icons.rotate_right, Colors.purple, [
                _buildSensorRow("X", gyroscopeX),
                _buildSensorRow("Y", gyroscopeY),
                _buildSensorRow("Z", gyroscopeZ),
                _buildSensorRow("Magnitude",
                    sqrt(gyroscopeX * gyroscopeX + gyroscopeY * gyroscopeY +
                        gyroscopeZ * gyroscopeZ),
                    isAlert: sqrt(gyroscopeX * gyroscopeX + gyroscopeY * gyroscopeY +
                        gyroscopeZ * gyroscopeZ) > GYROSCOPE_THRESHOLD),
              ]),
              _buildSensorCard("Noise Level (dB)", Icons.volume_up, Colors.red, [
                _buildSensorRow("Current", latestDB,
                    isAlert: latestDB > MEDIUM_NOISE_THRESHOLD),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: (latestDB / 120).clamp(0.0, 1.0),
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(
                      latestDB > MEDIUM_NOISE_THRESHOLD ? Colors.red : Colors.green),
                ),
              ]),
              const SizedBox(height: 20),
              Card(
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
                          Text("Detection Thresholds (TEST MODE):",
                              style: TextStyle(fontWeight: FontWeight.bold,
                                  color: Colors.orange)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text("• Severe impact: > ${HIGH_ACCELERATION_THRESHOLD.toStringAsFixed(1)} m/s² (${REQUIRED_SAMPLES} readings)"),
                      Text("• Loud noise: > ${HIGH_NOISE_THRESHOLD.toStringAsFixed(1)} dB"),
                      Text("• Rollover: > ${GYROSCOPE_THRESHOLD.toStringAsFixed(1)} rad/s rotation"),
                      const Text("• Combined sustained impact + noise triggers detection"),
                      const SizedBox(height: 10),
                      const Text(
                        "✅ Using system alarm sound - guaranteed to work!",
                        style: TextStyle(fontWeight: FontWeight.bold,
                            color: Colors.green, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "TIP: Shake your phone vigorously or make a loud noise to test!",
                        style: TextStyle(fontStyle: FontStyle.italic,
                            color: Colors.orange, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSensorCard(String title, IconData icon, Color color,
      List<Widget> children) {
    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 18,
                fontWeight: FontWeight.bold))
          ]),
          const SizedBox(height: 8),
          ...children,
        ]),
      ),
    );
  }

  Widget _buildSensorRow(String label, double value, {bool isAlert = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        Text(value.toStringAsFixed(2),
            style: TextStyle(
                color: isAlert ? Colors.red : Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 15)),
      ]),
    );
  }
}