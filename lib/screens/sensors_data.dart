import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:msg_bypas/screens/sos_screen.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:noise_meter/noise_meter.dart';
import 'package:audioplayers/audioplayers.dart';


class SosHelp extends StatefulWidget {
  const SosHelp({super.key});

  @override
  State<SosHelp> createState() => _SosHelpState();
}

class _SosHelpState extends State<SosHelp> {
  // Sensor data
  double accelerateX = 0.0, accelerateY = 0.0, accelerateZ = 0.0;
  double gyroscopeX = 0.0, gyroscopeY = 0.0, gyroscopeZ = 0.0;

  // Noise detection
  late NoiseMeter noiseMeter;
  bool isNoiseActive = false;
  StreamSubscription<NoiseReading>? noiseSubscription;
  double latestDB = 0.0;

  // Subscriptions
  StreamSubscription<AccelerometerEvent>? accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? gyroscopeSubscription;

  // Detection flags
  bool isAccidentDetected = false;
  bool isAlarmPlaying = false;

  // Timers
  Timer? uiUpdateTimer;

  // Counters
  int highAccelerationCount = 0;
  int highNoiseCount = 0;

  // Audio player
  final AudioPlayer player = AudioPlayer();

  // ==== Detection thresholds (realistic, tested values) ====
  static const double HIGH_ACCELERATION_THRESHOLD = 45.0; // ~4.5G severe impact
  static const double MEDIUM_ACCELERATION_THRESHOLD = 35.0; // ~3.5G strong impact
  static const double HIGH_NOISE_THRESHOLD = 95.0; // Loud crash, airbag
  static const double MEDIUM_NOISE_THRESHOLD = 90.0; // Screech or horn
  static const double GYROSCOPE_THRESHOLD = 6.5; // Sudden strong rotation
  static const int REQUIRED_SAMPLES = 4; // Must persist 4 readings
  static const int ALARM_DURATION = 30; // Seconds countdown

  // Adaptive smoothing
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

  // ---- NOISE ----
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
  // ---- SENSORS ----
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

  // ---- DETECTION LOGIC ----
  void checkForAccident() {
    if (isAccidentDetected) return;

    double accelerationMagnitude =
    sqrt(accelerateX * accelerateX + accelerateY * accelerateY + accelerateZ * accelerateZ);

    double gyroscopeMagnitude =
    sqrt(gyroscopeX * gyroscopeX + gyroscopeY * gyroscopeY + gyroscopeZ * gyroscopeZ);

    // Smooth small jitters
    recentAccelerations.add(accelerationMagnitude);
    if (recentAccelerations.length > SMOOTH_WINDOW) {
      recentAccelerations.removeAt(0);
    }
    double avgAccel = recentAccelerations.reduce((a, b) => a + b) / recentAccelerations.length;

    // Ignore normal placement or gravity
    if (avgAccel < 12.0) return; // phone still / normal gravity
    if (gyroscopeMagnitude < 0.5) return; // tiny rotation

    // Track sustained impact
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

    bool highImpact = avgAccel > HIGH_ACCELERATION_THRESHOLD && highAccelerationCount >= REQUIRED_SAMPLES;
    bool impactWithNoise = highAccelerationCount >= REQUIRED_SAMPLES && highNoiseCount >= REQUIRED_SAMPLES;
    bool noiseWithImpact = latestDB > HIGH_NOISE_THRESHOLD && avgAccel > MEDIUM_ACCELERATION_THRESHOLD;
    bool rollover = gyroscopeMagnitude > GYROSCOPE_THRESHOLD && highAccelerationCount >= REQUIRED_SAMPLES;

    if (highImpact || impactWithNoise || noiseWithImpact || rollover) {
      isAccidentDetected = true;
      highAccelerationCount = 0;
      highNoiseCount = 0;
      showAccidentDialog(context);
    }
  }

  // ---- ALERT DIALOG ----
  void showAccidentDialog(BuildContext context) async {
    int remainingSeconds = ALARM_DURATION;
    bool dismissed = false;
    Timer? countdownTimer;

    isAlarmPlaying = true;

    await player.setReleaseMode(ReleaseMode.loop);
    await player.play(AssetSource('images/Alert_alarm.wav'));

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          // Start countdown timer after dialog is built
          if (countdownTimer == null) {
            countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
              if (dismissed) {
                timer.cancel();
                return;
              }

              remainingSeconds--;
              setDialogState(() {}); // Update dialog UI

              if (remainingSeconds <= 0) {
                timer.cancel();
                if (Navigator.canPop(dialogContext)) {
                  Navigator.of(dialogContext).pop();
                }
                if (mounted) {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SosScreen()));
                }
                player.stop();
                isAccidentDetected = false;
                isAlarmPlaying = false;
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
                  Text('ACCIDENT DETECTED!',
                      style: TextStyle(color: Colors.red, fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Emergency services will be contacted in:',
                      textAlign: TextAlign.center),
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
                      backgroundColor: Colors.green, foregroundColor: Colors.white),
                  onPressed: () {
                    dismissed = true;
                    countdownTimer?.cancel();
                    player.stop();
                    Navigator.of(dialogContext).pop();
                    setState(() {
                      isAccidentDetected = false;
                      isAlarmPlaying = false;
                    });
                  },
                  child: const Text("I'M SAFE", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                      backgroundColor: Colors.red, foregroundColor: Colors.white),
                  onPressed: () {
                    dismissed = true;
                    countdownTimer?.cancel();
                    player.stop();
                    Navigator.of(dialogContext).pop();
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const SosScreen()));
                    setState(() {
                      isAccidentDetected = false;
                      isAlarmPlaying = false;
                    });
                  },
                  child: const Text('CALL SOS NOW',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    noiseSubscription?.cancel();
    accelerometerSubscription?.cancel();
    gyroscopeSubscription?.cancel();
    uiUpdateTimer?.cancel();
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double accelerationMagnitude =
    sqrt(accelerateX * accelerateX + accelerateY * accelerateY + accelerateZ * accelerateZ);

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
              // Status
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
              ]),
              _buildSensorCard("Noise Level (dB)", Icons.volume_up, Colors.red, [
                _buildSensorRow("Current", latestDB, isAlert: latestDB > MEDIUM_NOISE_THRESHOLD),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: (latestDB / 120).clamp(0.0, 1.0),
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(
                      latestDB > MEDIUM_NOISE_THRESHOLD ? Colors.red : Colors.green),
                ),
              ]),
              const SizedBox(height: 20),
              const Card(
                elevation: 3,
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Detection Thresholds:",
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 6),
                      Text("• Severe impact: > 45 m/s² (sustained 4 readings)"),
                      Text("• Loud crash: > 95 dB"),
                      Text("• Rollover: > 6.5 rad/s rotation"),
                      Text("• Combined sustained impact + noise triggers detection"),
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

  Widget _buildSensorCard(String title, IconData icon, Color color, List<Widget> children) {
    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))
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