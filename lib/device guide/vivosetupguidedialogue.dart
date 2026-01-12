import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class VivoSetupGuideDialog extends StatelessWidget {
  final String manufacturer;
  final String model;

  const VivoSetupGuideDialog({
    Key? key,
    required this.manufacturer,
    required this.model,
  }) : super(key: key);

  static const serviceChannel = MethodChannel('com.buxhiisd.msg_bypas/service');

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.settings, color: Colors.orange.shade700, size: 28),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              '⚙️ Vivo Setup Required',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
              'Device: $manufacturer $model',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'For reliable SMS sending in emergencies, please complete these steps:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            _buildStep(
              '1',
              'Allow Autostart',
              'Tap "Enable Autostart" below, then find "Rescue Me" and enable it',
              Colors.red,
            ),
            const SizedBox(height: 12),
            _buildStep(
              '2',
              'Disable Battery Optimization',
              'Allow app to run in background without restrictions',
              Colors.orange,
            ),
            const SizedBox(height: 12),
            _buildStep(
              '3',
              'Allow Background Activity',
              'Enable "Allow background activity" in app settings',
              Colors.green,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Why is this needed?',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Vivo devices have aggressive battery optimization that can block emergency SMS. These settings ensure the app can send SMS even when closed.',
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
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Later'),
        ),
        ElevatedButton.icon(
          onPressed: () async {
            await serviceChannel.invokeMethod('requestAutoStartPermission');
          },
          icon: const Icon(Icons.power_settings_new, size: 20),
          label: const Text('Enable Autostart'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
        ),
        ElevatedButton.icon(
          onPressed: () async {
            await serviceChannel.invokeMethod('openVivoSettings');
          },
          icon: const Icon(Icons.settings, size: 20),
          label: const Text('Open Settings'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildStep(String number, String title, String description, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static Future<void> show(BuildContext context) async {
    try {
      const smsChannel = MethodChannel('com.buxhiisd.msg_bypas/sms');
      final deviceInfo = await smsChannel.invokeMethod('getDeviceInfo') as Map;

      final manufacturer = deviceInfo['manufacturer'] as String;
      final model = deviceInfo['model'] as String;

      if (manufacturer.toLowerCase().contains('vivo')) {
        if (context.mounted) {
          showDialog(
            context: context,
            builder: (ctx) => VivoSetupGuideDialog(
              manufacturer: manufacturer,
              model: model,
            ),
          );
        }
      }
    } catch (e) {
      print('Error showing Vivo guide: $e');
    }
  }
}

// Extension method to easily show the dialog
extension VivoGuideExtension on BuildContext {
  Future<void> showVivoGuideIfNeeded() async {
    await VivoSetupGuideDialog.show(this);
  }
}