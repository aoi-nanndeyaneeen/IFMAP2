// ifmap_editor/lib/json_exporter.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'config.dart';
import 'map_cell.dart';

class JsonExporter {
  static void export(BuildContext context, List<List<MapCell>> grid) {
    final nodes = <String, dynamic>{};
    for (int y = 0; y < AppConfig.rows; y++) {
      for (int x = 0; x < AppConfig.cols; x++) {
        final cell = grid[y][x];
        if (!cell.isWalkable) continue;
        final id     = cell.name ?? 'node_$y-$x';
        final edges  = <String>[];
        for (final d in [[-1,0],[1,0],[0,-1],[0,1]]) {
          final ny = y + d[0], nx = x + d[1];
          if (ny >= 0 && ny < AppConfig.rows && nx >= 0 && nx < AppConfig.cols && grid[ny][nx].isWalkable) {
            edges.add(grid[ny][nx].name ?? 'node_$ny-$nx');
          }
        }
        nodes[id] = {
          'x': x * AppConfig.pxPerCell,
          'y': y * AppConfig.pxPerCell,
          'edges': edges,
          if (cell.type == 4) 'isStairs':   true,
          if (cell.type == 5) 'isConnector': true,
          if (cell.type == 5 && cell.connectsToMap  != null) 'connectsToMap':  cell.connectsToMap,
          if (cell.type == 5 && cell.connectsToNode != null) 'connectsToNode': cell.connectsToNode,
        };
      }
    }
    final json = const JsonEncoder.withIndent('  ').convert(nodes);
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('生成された nodes.json'),
      content: SizedBox(width: double.maxFinite, child: SingleChildScrollView(child: SelectableText(json))),
      actions: [
        ElevatedButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: json));
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('コピーしました')));
          },
          icon: const Icon(Icons.copy), label: const Text('コピー'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる')),
      ],
    ));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ifmap_editor/lib/tool_palette.dart
// ─────────────────────────────────────────────────────────────────────────────