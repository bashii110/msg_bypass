import 'package:flutter/material.dart';
import 'package:msg_bypas/screens/sensors_data.dart';
import 'package:msg_bypas/screens/settings_scrren.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/accident_service.dart';
import '../services/sms_service.dart';
import '../services/oppo_vivo_helper.dart';
import 'msg_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AccidentDetectionService _detectionService = AccidentDetectionService();
  bool _isMonitoring = false;
  String _emergencyNumber = '';
  String _emergencyName = '';
  bool _isLoading = false;
  bool _isRestrictedDevice = false;
  String _manufacturer = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkDevice();
  }

  @override
  void dispose() {
    _detectionService.dispose();
    super.dispose();
  }

  Future<void> _checkDevice() async {
    final isRestricted = await OppoVivoHelper.isRestrictedDevice();
    final manufacturer = await OppoVivoHelper.getManufacturer();

    setState(() {
      _isRestrictedDevice = isRestricted;
      _manufacturer = manufacturer;
    });

    // Show setup dialog if needed
    if (isRestricted) {
      final prefs = await SharedPreferences.getInstance();
      final hasShownGuide = prefs.getBool('home_device_setup_shown') ?? false;

      if (!hasShownGuide && mounted) {
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            _showDeviceSetupDialog();
            prefs.setBool('home_device_setup_shown', true);
          }
        });
      }
    }
  }

  void _showDeviceSetupDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber, color: Colors.orange, size: 28),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${_manufacturer.toUpperCase()} Device Setup'),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '⚠️ CRITICAL FOR EMERGENCY ALERTS ⚠️\n',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                  fontSize: 14,
                ),
              ),
              Text(
                OppoVivoHelper.getManufacturerSpecificInstructions(
                    _manufacturer),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade300, width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error, color: Colors.red.shade700, size: 24),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Without these settings, SMS may only open your messaging app instead of sending automatically!',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('I\'ll Do It Later'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.of(ctx).pop();

              bool opened = await OppoVivoHelper.openAutoStartSettings();

              if (!opened) {
                const packageName =
                    'com.buxhiisd.msg_bypas'; // Replace with your package
                await OppoVivoHelper.openAppSettings(packageName);
              }
            },
            icon: const Icon(Icons.settings),
            label: const Text('Open Settings'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _emergencyNumber = prefs.getString('emergency_number') ?? '';
      _emergencyName = prefs.getString('emergency_name') ?? 'Emergency Contact';
      _isMonitoring = prefs.getBool('monitoring_enabled') ?? false;
    });

    if (_isMonitoring) {
      _detectionService.startMonitoring();
    }
  }

  Future<void> _toggleMonitoring() async {
    setState(() => _isMonitoring = !_isMonitoring);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('monitoring_enabled', _isMonitoring);

    if (_isMonitoring) {
      _detectionService.startMonitoring();
      _showSnackBar('Accident detection started', Colors.green);
    } else {
      _detectionService.stopMonitoring();
      _showSnackBar('Accident detection stopped', Colors.orange);
    }
  }

  Future<void> _sendTestAlert() async {
    setState(() => _isLoading = true);

    try {
      bool sent = await SMSService.sendQuickEmergencySMS(_emergencyNumber);

      if (sent) {
        _showSnackBar('Test alert sent successfully!', Colors.green);
      } else {
        _showSnackBar('Failed to send test alert', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Error: $e', Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _sendManualAlert() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send Emergency Alert?'),
        content: Text(
            'This will send an emergency SMS with your location to $_emergencyName.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Send Alert'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);

      try {
        bool sent = await SMSService.sendEmergencySMS(_emergencyNumber);

        if (sent) {
          _showSnackBar('Emergency alert sent!', Colors.green);
        } else {
          _showSnackBar('Failed to send alert', Colors.red);
        }
      } catch (e) {
        _showSnackBar('Error: $e', Colors.red);
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency SMS'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              _loadSettings();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Warning banner for restricted devices
          if (_isRestrictedDevice)
            Material(
              color: Colors.orange.shade100,
              child: InkWell(
                onTap: _showDeviceSetupDialog,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber, color: Colors.orange.shade900),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_manufacturer.toUpperCase()} Device',
                              style: TextStyle(
                                color: Colors.orange.shade900,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              'Tap here for required settings',
                              style: TextStyle(
                                color: Colors.orange.shade800,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios,
                        color: Colors.orange.shade900,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildStatusCard(),
                  const SizedBox(height: 16),
                  _buildEmergencyContactCard(),
                  const SizedBox(height: 16),
                  _buildQuickActionsCard(),
                  const SizedBox(height: 16),
                  _sensorsButton(),
                  const SizedBox(height: 16),
                  _buildInfoCard(),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isLoading ? null : _sendManualAlert,
        backgroundColor: Colors.red,
        icon: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Icon(Icons.emergency),
        label: const Text('SEND SOS'),
      ),
    );
  }

  //Method for active monitering
  Widget _buildStatusCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              _isMonitoring ? Icons.sensors : Icons.sensors_off,
              size: 64,
              color: _isMonitoring ? Colors.green : Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              _isMonitoring ? 'Monitoring Active' : 'Monitoring Inactive',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isMonitoring
                  ? 'Accident detection is running'
                  : 'Tap below to start monitoring',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _toggleMonitoring,
                icon: Icon(_isMonitoring ? Icons.stop : Icons.play_arrow),
                label: Text(
                    _isMonitoring ? 'Stop Monitoring' : 'Start Monitoring'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: _isMonitoring ? Colors.orange : Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  //emergency Contact method
  Widget _buildEmergencyContactCard() {
    return Card(
      elevation: 2,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).primaryColor,
          child: const Icon(Icons.person, color: Colors.white),
        ),
        title: Text(
          _emergencyName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(_emergencyNumber),
        trailing: IconButton(
          icon: const Icon(Icons.edit),
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            );
            _loadSettings();
          },
        ),
      ),
    );
  }

  //Method for quick actions
  Widget _buildQuickActionsCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Quick Actions',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _sendTestAlert,
                    icon: const Icon(Icons.send),
                    label: const Text('Test Alert'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const MessagesScreen()),
                      );
                    },
                    icon: const Icon(Icons.message),
                    label: const Text('Messages'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  //Sensors Button
  Widget _sensorsButton() {
    return SizedBox(
      width: double.infinity,
      // height: 20,
      child: FilledButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const SosHelp(),
              ),
            );
          },
          child: const Text("See Sensor Data")),
    );
  }

  //Information card
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
                Text(
                  'How It Works',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoItem('• Monitors device sensors for sudden impacts'),
            _buildInfoItem('• Automatically detects potential accidents'),
            _buildInfoItem('• Sends SMS with your GPS location'),
            _buildInfoItem('• Includes Google Maps link for quick navigation'),
            _buildInfoItem('• Works in background with monitoring enabled'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.blue.shade900,
          fontSize: 13,
        ),
      ),
    );
  }
}
