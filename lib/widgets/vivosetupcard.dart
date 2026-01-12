import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';

class VivoSetupCard extends StatefulWidget {
  const VivoSetupCard({Key? key}) : super(key: key);

  @override
  State<VivoSetupCard> createState() => _VivoSetupCardState();
}

class _VivoSetupCardState extends State<VivoSetupCard> {
  bool _isVivoDevice = false;
  bool _isLoading = true;
  String _manufacturer = '';
  String _model = '';

  static const serviceChannel = MethodChannel('com.buxhiisd.msg_bypas/service');

  @override
  void initState() {
    super.initState();
    _checkDevice();
  }

  Future<void> _checkDevice() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;

      setState(() {
        _manufacturer = androidInfo.manufacturer;
        _model = androidInfo.model;
        _isVivoDevice = _manufacturer.toLowerCase().contains('vivo');
        _isLoading = false;
      });
    } catch (e) {
      print('Error checking device: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox.shrink();
    }

    if (!_isVivoDevice) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 4,
      color: Colors.orange.shade50,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '⚠️ Vivo Device Detected',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '$_manufacturer $_model',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'For reliable emergency SMS, you MUST complete these steps:',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            _buildCheckItem('Enable "Autostart" permission'),
            _buildCheckItem('Allow "Background activity"'),
            _buildCheckItem('Disable "Battery optimization"'),
            _buildCheckItem('Grant all SMS permissions'),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showDetailedGuide(context),
                    icon: const Icon(Icons.info_outline, size: 18),
                    label: const Text('View Guide'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange.shade700,
                      side: BorderSide(color: Colors.orange.shade300),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _openVivoSettings,
                    icon: const Icon(Icons.settings, size: 18),
                    label: const Text('Open Settings'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade700,
                      foregroundColor: Colors.white,
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

  Widget _buildCheckItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, size: 18, color: Colors.orange.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openVivoSettings() async {
    try {
      await serviceChannel.invokeMethod('openVivoSettings');
    } catch (e) {
      print('Error opening Vivo settings: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open settings: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showDetailedGuide(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.phone_android, color: Colors.orange.shade700),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Vivo Setup Guide',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Device: $_manufacturer $_model',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
              ),
              const SizedBox(height: 16),
              _buildGuideSection(
                '1️⃣ Enable Autostart',
                [
                  'Go to Settings → Apps → Rescue Me',
                  'Find "Autostart" or "Auto-launch"',
                  'Toggle it ON (should turn blue)',
                  'This allows the app to start in background',
                ],
              ),
              const SizedBox(height: 16),
              _buildGuideSection(
                '2️⃣ Allow Background Activity',
                [
                  'In the same Settings → Apps → Rescue Me',
                  'Find "Background activity" or "Background permissions"',
                  'Enable "Allow background activity"',
                  'This lets the app run when screen is off',
                ],
              ),
              const SizedBox(height: 16),
              _buildGuideSection(
                '3️⃣ Disable Battery Optimization',
                [
                  'Settings → Battery',
                  'Find "Rescue Me" in the app list',
                  'Change from "Optimize" to "Don\'t optimize"',
                  'Or select "No restrictions"',
                ],
              ),
              const SizedBox(height: 16),
              _buildGuideSection(
                '4️⃣ Grant SMS Permissions',
                [
                  'Settings → Apps → Rescue Me → Permissions',
                  'Enable "SMS" permission',
                  'Enable "Phone" permission',
                  'Enable "Location" permission',
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning, color: Colors.red.shade700, size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'CRITICAL',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Without these settings, emergency SMS may NOT be sent when you need help. Vivo devices are known to aggressively kill background apps.',
                      style: TextStyle(fontSize: 12),
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
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              _openVivoSettings();
            },
            icon: const Icon(Icons.settings, size: 18),
            label: const Text('Open Settings'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuideSection(String title, List<String> steps) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        ...steps.map((step) => Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('• ', style: TextStyle(fontSize: 12)),
              Expanded(
                child: Text(
                  step,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        )),
      ],
    );
  }
}