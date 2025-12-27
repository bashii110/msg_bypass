import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/permission_service.dart';
import '../services/oppo_vivo_helper.dart';
import 'home_screen.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({Key? key}) : super(key: key);

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  bool _isLoading = false;
  int _currentStep = 0;
  bool _isRestrictedDevice = false;
  String _manufacturer = '';

  @override
  void initState() {
    super.initState();
    _checkDevice();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _checkDevice() async {
    final isRestricted = await OppoVivoHelper.isRestrictedDevice();
    final manufacturer = await OppoVivoHelper.getManufacturer();

    setState(() {
      _isRestrictedDevice = isRestricted;
      _manufacturer = manufacturer;
    });
  }

  Future<void> _requestPermissions() async {
    setState(() => _isLoading = true);

    try {
      bool granted = await PermissionService.requestAllPermissions();

      if (granted) {
        // If it's a restricted device, show special instructions
        if (_isRestrictedDevice) {
          _showRestrictedDeviceDialog();
        } else {
          setState(() => _currentStep = 1);
        }
      } else {
        _showErrorDialog('Permissions Required',
            'Please grant all permissions for the app to function properly.');
      }
    } catch (e) {
      _showErrorDialog('Error', 'Failed to request permissions: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showRestrictedDeviceDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber, color: Colors.orange),
            const SizedBox(width: 8),
            Text('${_manufacturer.toUpperCase()} Device Detected'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'For this life-saving app to work properly on your device, you MUST complete these steps:\n',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(OppoVivoHelper.getManufacturerSpecificInstructions(_manufacturer)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Without these settings, emergency SMS may not be sent!',
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
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() => _currentStep = 1);
            },
            child: const Text('I\'ll Do It Later'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();

              // Try to open auto-start settings first
              bool opened = await OppoVivoHelper.openAutoStartSettings();

              if (!opened) {
                // Fallback to app settings
                const packageName = 'com.buxhiisd.msg_bypas'; // Replace with your package
                await OppoVivoHelper.openAppSettings(packageName);
              }

              // Move to next step after showing settings
              Future.delayed(const Duration(seconds: 1), () {
                if (mounted) {
                  setState(() => _currentStep = 1);
                }
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
            child: const Text('Open Settings Now'),
          ),
        ],
      ),
    );
  }

  Future<void> _completeSetup() async {
    if (_phoneController.text.isEmpty) {
      _showErrorDialog('Error', 'Please enter an emergency contact number');
      return;
    }

    if (_nameController.text.isEmpty) {
      _showErrorDialog('Error', 'Please enter the contact name');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('emergency_number', _phoneController.text);
      await prefs.setString('emergency_name', _nameController.text);
      await prefs.setBool('is_setup', true);

      // Request battery optimization exemption for restricted devices
      if (_isRestrictedDevice) {
        const packageName = 'com.buxhiisd.msg_bypas'; // Replace with your package
        await OppoVivoHelper.requestBatteryOptimizationExemption(packageName);
      }

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } catch (e) {
      _showErrorDialog('Error', 'Failed to save settings: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Setup Emergency SMS'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Show warning banner for restricted devices
          if (_isRestrictedDevice)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.orange.shade100,
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.orange.shade900),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_manufacturer.toUpperCase()} device: Additional setup required!',
                      style: TextStyle(
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Stepper(
              currentStep: _currentStep,
              onStepContinue: () {
                if (_currentStep == 0) {
                  _requestPermissions();
                } else if (_currentStep == 1) {
                  _completeSetup();
                }
              },
              onStepCancel: () {
                if (_currentStep > 0) {
                  setState(() => _currentStep--);
                }
              },
              controlsBuilder: (context, details) {
                return Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Row(
                    children: [
                      ElevatedButton(
                        onPressed: _isLoading ? null : details.onStepContinue,
                        child: _isLoading
                            ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                            : Text(_currentStep == 1 ? 'Complete' : 'Continue'),
                      ),
                      const SizedBox(width: 8),
                      if (_currentStep > 0)
                        TextButton(
                          onPressed: _isLoading ? null : details.onStepCancel,
                          child: const Text('Back'),
                        ),
                    ],
                  ),
                );
              },
              steps: [
                Step(
                  title: const Text('Permissions'),
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'This app requires the following permissions to function:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      _buildPermissionTile(
                        Icons.sms,
                        'SMS',
                        'Send emergency messages',
                      ),
                      _buildPermissionTile(
                        Icons.location_on,
                        'Location',
                        'Share your location in emergencies',
                      ),
                      _buildPermissionTile(
                        Icons.notifications,
                        'Notifications',
                        'Alert you of app status',
                      ),
                      _buildPermissionTile(
                        Icons.phone,
                        'Phone',
                        'Access phone state',
                      ),
                    ],
                  ),
                  isActive: _currentStep >= 0,
                  state: _currentStep > 0 ? StepState.complete : StepState.indexed,
                ),
                Step(
                  title: const Text('Emergency Contact'),
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Enter the phone number that will receive emergency alerts:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: 'Contact Name',
                          hintText: 'e.g., Mom, Dad, Emergency Contact',
                          prefixIcon: const Icon(Icons.person),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: 'Phone Number',
                          hintText: '+923001234567',
                          prefixIcon: const Icon(Icons.phone),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          border: Border.all(color: Colors.amber.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.amber.shade700),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'This number will receive automatic SMS alerts when an accident is detected.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  isActive: _currentStep >= 1,
                  state: _currentStep > 1 ? StepState.complete : StepState.indexed,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionTile(IconData icon, String title, String subtitle) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).primaryColor),
      title: Text(title),
      subtitle: Text(subtitle),
      contentPadding: EdgeInsets.zero,
    );
  }
}