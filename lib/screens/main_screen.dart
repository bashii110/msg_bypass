import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:msg_bypas/screens/emergencycontactscreen.dart';
import 'package:msg_bypas/screens/home_screen.dart';
import 'package:msg_bypas/screens/settings_scrren.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {

  int _currentIndex = 0;

  final List<Widget> _screens = [

    const HomeScreen(),
    const EmergencyContactsScreen(),
    SettingsScreen(),
    // NotificationsPage(),
    // ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(


      body: _screens[_currentIndex], // Show selected screen
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        selectedItemColor: Colors.blueAccent,
        selectedFontSize: 18,
        unselectedFontSize: 14,
        // unselectedItemColor: Colors.black,

        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: "Home",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.contacts),
            label: "Contact",
          ),


          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: "Settings",

          ),

          // BottomNavigationBarItem(
          //   icon: Icon(Icons.map_outlined),
          //   label: "Maps",
          // ),
          // BottomNavigationBarItem(
          //   icon: Icon(Icons.notifications_none_outlined),
          //   label: "Notifications",
          //
          // ),
        ],
      ),
    );
  }
}
