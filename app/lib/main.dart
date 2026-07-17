import 'package:flutter/material.dart';

import 'notifications.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Notifications.init(); // best-effort; countdown-timer alerts
  runApp(const RpgMeApp());
}

class RpgMeApp extends StatelessWidget {
  const RpgMeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RPG_me',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4C72B0)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
