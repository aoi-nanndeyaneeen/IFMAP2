import 'package:flutter/material.dart';
import 'map_screen.dart'; // 分割した画面ファイルを読み込む

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
      home: const MapScreen(), // MapScreenを呼び出すだけ
    );
  }
}