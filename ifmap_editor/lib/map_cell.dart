// lib/map_cell.dart
import 'package:flutter/material.dart';

class MapCell {
  final int x;
  final int y;
  int type; // 0: 空白/壁, 1: 通路, 3: 目的地, 4: 階段
  String? name;

  MapCell({required this.x, required this.y, this.type = 0, this.name});

  // セルの色
  Color get color {
    switch (type) {
      case 1: return Colors.blue.withValues(alpha: 0.5); // 通路
      case 3: return Colors.yellow.shade600.withValues(alpha: 0.8); // 目的地(黄色)
      case 4: return Colors.green.withValues(alpha: 0.8); // 階段(緑)
      default: return Colors.transparent;
    }
  }

  // 歩ける場所かどうか（階段も歩けます）
  bool get isWalkable => type == 1 || type == 3 || type == 4;
}