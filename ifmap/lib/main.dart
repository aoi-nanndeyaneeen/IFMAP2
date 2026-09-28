// lib/main.dart
import 'package:flutter/material.dart';

import 'ui/map_screen.dart';

void main() {
  runApp(const IfMapApp());
}

class IfMapApp extends StatelessWidget {
  const IfMapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ifmap',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MapScreen(),
    );
  }
}
