import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const GemmaBiteApp());
}

class GemmaBiteApp extends StatelessWidget {
  const GemmaBiteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gemma Bite',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
