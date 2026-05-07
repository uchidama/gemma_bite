import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const GemmaBiteApp());
}

class GemmaBiteApp extends StatefulWidget {
  const GemmaBiteApp({super.key});

  @override
  State<GemmaBiteApp> createState() => _GemmaBiteAppState();
}

class _GemmaBiteAppState extends State<GemmaBiteApp> {
  ThemeMode _themeMode = ThemeMode.light;

  void _setThemeMode(ThemeMode themeMode) {
    setState(() => _themeMode = themeMode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gemma Bite',
      themeMode: _themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: Colors.black,
        cardColor: const Color(0xFF1E1E1E),
        useMaterial3: true,
      ),
      home: HomeScreen(
        themeMode: _themeMode,
        onThemeModeChanged: _setThemeMode,
      ),
    );
  }
}
