// ifmap_editor/lib/map_cell.dart
import 'package:flutter/material.dart';

class MapCell {
  final int x, y;
  int     type; // 0:空白 1:通路 3:目的地/QR 4:階段 5:接続点(別棟・別フロアへ) 6:屋外(芗生・フィールド)
  String? name;
  // type==5 のみ使用
  String? connectsToMap;  // 接続先マップラベル (例: '新館1F')
  String? connectsToNode; // 接続先ノードID    (例: 'connector_from_main')

  bool wallTop;
  bool wallRight;
  bool wallBottom;
  bool wallLeft;

  bool doorTop;
  bool doorRight;
  bool doorBottom;
  bool doorLeft;

  MapCell({required this.x, required this.y, this.type = 0,
           this.name, this.connectsToMap, this.connectsToNode,
           this.wallTop = false, this.wallRight = false, this.wallBottom = false, this.wallLeft = false,
           this.doorTop = false, this.doorRight = false, this.doorBottom = false, this.doorLeft = false});

  Color get color {
    switch (type) {
      case 1: return Colors.blue.withValues(alpha: 0.25);
      case 3: 
        if (name == null || name!.isEmpty) return Colors.yellow.shade600.withValues(alpha: 0.35);
        final hash = name.hashCode;
        // 黄色〜オレンジの範囲に限定 (Hue: 35 - 55)
        final hue = 35.0 + ((hash.abs() % 100) / 100.0) * 20.0;
        final sat = 0.6 + ((hash.abs() ~/ 100) % 40) / 100.0; 
        final lit = 0.45 + ((hash.abs() ~/ 10000) % 20) / 100.0; 
        return HSLColor.fromAHSL(0.35, hue, sat, lit).toColor();
      case 4: return Colors.green.withValues(alpha: 0.45);
      case 5: return Colors.deepPurple.withValues(alpha: 0.45);
      case 6: return Colors.lightGreen.withValues(alpha: 0.45);
      case 10: return Colors.blueGrey.withValues(alpha: 0.5); // 装飾用（建物外観など）
      default: return Colors.transparent;
    }
  }

  bool get isWalkable => type == 1 || type == 3 || type == 4 || type == 5 || type == 6;
 
  bool isWall(String dir) => switch (dir) {
    'top'    => wallTop,
    'bottom' => wallBottom,
    'left'   => wallLeft,
    'right'  => wallRight,
    _        => false,
  };
 
  bool isDoor(String dir) => switch (dir) {
    'top'    => doorTop,
    'bottom' => doorBottom,
    'left'   => doorLeft,
    'right'  => doorRight,
    _        => false,
  };
}