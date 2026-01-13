import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Detailed step-by-step guide for OPPO users
/// Show this when user taps "View Instructions" button
class OPPOSetupScreen extends StatelessWidget {
  static const serviceChannel = MethodChannel('com.buxhiisd.msg_bypas/service');

  const OPPOSetupScreen({Key? key}) : super(key: key);

  Future<void> _openSettings() async {
    try {
      await serviceChannel.invokeMethod('openOPPOSettings');
    } catch (e) {
      print('Error opening settings: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OPPO Setup Guide'),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildWarningBanner(),
          const SizedBox(height: 20),

          _buildStep(
            number: 1,
            title: 'Disable Battery Optimization',
            importance: '🔴 MOST CRITICAL',
            description: 'Without this, app stops after 3-4 days!',
            methods: [
              StepMethod(
                title: 'Method A (Easiest)',
                steps: [
                  'Open Settings',
                  'Go to Battery',
                  'Tap (⋮) three dots menu',
                  'Select "Special access"',
                  'Tap "Battery optimization"',
                  'Find "Rescue Me" in the list',
                  'Select "Don\'t optimize"',
                  'Tap Done',
                ],
              ),
              StepMethod(
                title: 'Method B (Alternative)',
                steps: [
                  'Open Settings',
                  'Go to Apps',
                  'Find and tap "Rescue Me"',
                  'Tap "Battery"',
                  'Tap "Battery optimization"',
                  'Select "Don\'t optimize"',
                ],
              ),
            ],
          ),

          const Divider(height: 40, thickness: 2),

          _buildStep(
            number: 2,
            title: 'Lock App in Recent Apps',
            importance: '🔴 CRITICAL',
            description: 'Prevents system from closing the app',
            methods: [
              StepMethod(
                title: 'How to Lock',
                steps: [
                  'Press the Recent Apps button (square icon)',
                  'Swipe through apps to find "Rescue Me"',
                  'Pull down on the app card',
                  'OR tap the lock icon 🔒 at top',
                  'A lock icon should appear on the card',
                  'This prevents app from being closed',
                ],
              ),
            ],
          ),

          const Divider(height: 40, thickness: 2),

          _buildStep(
            number: 3,
            title: 'Allow All Permissions',
            importance: '🟠 REQUIRED',
            description: 'App needs SMS, Phone, Location permissions',
            methods: [
              StepMethod(
                title: 'Grant Permissions',
                steps: [
                  'Open Settings',
                  'Go to Apps',
                  'Find and tap "Rescue Me"',
                  'Tap "Permissions"',
                  'Allow ALL permissions:',
                  '  • SMS (required for emergency messages)',
                  '  • Phone (required for emergency calls)',
                  '  • Location → "Allow all the time"',
                  '  • Notifications',
                ],
              ),
            ],
          ),

          const Divider(height: 40, thickness: 2),

          _buildStep(
            number: 4,
            title: 'Allow Background Activity',
            importance: '🟠 REQUIRED',
            description: 'Lets app monitor sensors in background',
            methods: [
              StepMethod(
                title: 'Enable Background',
                steps: [
                  'Open Settings',
                  'Go to Apps',
                  'Find and tap "Rescue Me"',
                  'Look for "Background activity" or "Background restrictions"',
                  'Set to "Allowed" or "No restrictions"',
                ],
              ),
            ],
          ),

          const SizedBox(height: 30),

          _buildActionButtons(context),

          const SizedBox(height: 20),

          _buildTestSection(),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildWarningBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red, width: 2),
      ),
      child: Column(
        children: [
          Icon(Icons.warning_amber_rounded, size: 48, color: Colors.red.shade700),
          const SizedBox(height: 12),
          const Text(
            '⚠️ CRITICAL WARNING',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'OPPO phones aggressively kill background apps.\n'
                'If you skip ANY step below, this life-saving app will STOP WORKING after 3-4 days!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildStep({
    required int number,
    required String title,
    required String importance,
    required String description,
    required List<StepMethod> methods,
  }) {
    return Card(
      elevation: 3,
      child: ExpansionTile(
        initiallyExpanded: number == 1, // First step expanded by default
        leading: CircleAvatar(
          backgroundColor: number <= 2 ? Colors.red : Colors.orange,
          foregroundColor: Colors.white,
          child: Text('$number', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              importance,
              style: TextStyle(
                color: number <= 2 ? Colors.red : Colors.orange,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            Text(description, style: const TextStyle(fontSize: 12)),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: methods.map((method) => _buildMethod(method)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMethod(StepMethod method) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          method.title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Colors.blue,
          ),
        ),
        const SizedBox(height: 8),
        ...method.steps.asMap().entries.map((entry) {
          final index = entry.key;
          final step = entry.value;
          return Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${index + 1}. ',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Expanded(
                  child: Text(step),
                ),
              ],
            ),
          );
        }).toList(),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _openSettings,
            icon: const Icon(Icons.settings, size: 24),
            label: const Text(
              'OPEN SETTINGS NOW',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.check_circle, size: 24),
            label: const Text(
              'I COMPLETED ALL STEPS',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.green,
              side: const BorderSide(color: Colors.green, width: 2),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTestSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.science, color: Colors.blue),
              const SizedBox(width: 8),
              const Text(
                '🧪 Test Your Setup',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'After completing all steps:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('1. Enable monitoring in the app'),
          const Text('2. Lock your phone'),
          const Text('3. Wait 10-15 minutes'),
          const Text('4. Unlock and check if monitoring is still active'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'If still active = Setup successful! ✅',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.error, color: Colors.red, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'If stopped = Review steps again ❌',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
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

class StepMethod {
  final String title;
  final List<String> steps;

  StepMethod({required this.title, required this.steps});
}