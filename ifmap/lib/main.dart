// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui/map_screen.dart';
import 'ui/theme.dart';

void main() {
  runApp(const IfMapApp());
}

class IfMapApp extends StatelessWidget {
  const IfMapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: MaterialApp(
        title: 'infacilityMAP',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: const MapScreen(),
      ),
    );
  }
}
