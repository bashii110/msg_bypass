import 'package:flutter/material.dart';

class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
          child: Column(
            children: [
              Text(
                "Add Contacts",
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
              )
            ],
          )),
    );
  }
}
