// lib/json_exporter.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // クリップボード機能を追加！
import 'config.dart';
import 'map_cell.dart';

class JsonExporter {
  static void export(BuildContext context, List<List<MapCell>> grid) {
    Map<String, dynamic> nodesData = {};
    for (int y = 0; y < AppConfig.rows; y++) {
      for (int x = 0; x < AppConfig.cols; x++) {
        MapCell cell = grid[y][x];
        if (cell.isWalkable) {
          String nodeId = cell.name ?? 'node_$y-$x';
          List<String> edges = [];
          List<List<int>> directions = [[-1, 0], [1, 0], [0, -1], [0, 1]];
          for (var dir in directions) {
            int ny = y + dir[0], nx = x + dir[1];
            if (ny >= 0 && ny < AppConfig.rows && nx >= 0 && nx < AppConfig.cols) {
              if (grid[ny][nx].isWalkable) edges.add(grid[ny][nx].name ?? 'node_$ny-$nx');
            }
          }
          nodesData[nodeId] = {
            "x": x * 10,
            "y": y * 10,
            "edges": edges,
            if (cell.type == 4) "isStairs": true
          };
        }
      }
    }
    String jsonString = const JsonEncoder.withIndent('  ').convert(nodesData);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('生成された nodes.json'),
        content: SizedBox(width: double.maxFinite, child: SingleChildScrollView(child: SelectableText(jsonString))),
        actions: [
          // 【新機能】ワンクリックで完璧なテキストをコピーするボタン！
          ElevatedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: jsonString));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('クリップボードにコピーしました！')),
                );
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('コピーする'),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))
        ],
      ),
    );
  }
}