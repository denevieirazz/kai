import 'package:flutter/material.dart';
import 'screens/main_layout.dart';

void main() {
  runApp(const HubApp());
}

class HubApp extends StatelessWidget {
  const HubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hub Arsenal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.deepPurpleAccent,
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Colors.deepPurpleAccent,
          secondary: Colors.tealAccent,
        ),
      ),
      home: const MainLayout(),
    );
  }
}
