import 'dart:convert';
import 'dart:typed_data';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'config.dart';
import 'map_cell.dart';

class JsonExporter {
  static void export(BuildContext context, List<List<MapCell>> grid, Uint8List? bgImageBytes) {
    if (!context.mounted) return;
    
    // UIをブロックしないように、少し処理を遅延させます
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('JSONの生成とダウンロードを準備中です...')));

    Future.microtask(() {
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

      final editorData = {
        'bgImageBase64': bgImageBytes != null ? base64Encode(bgImageBytes!) : null,
        'cells': grid.expand((row) => row).where((c) => c.type != 0).map((c) => {
          'x': c.x, 'y': c.y, 'type': c.type,
          if (c.name != null) 'name': c.name,
          if (c.connectsToMap != null) 'connectsToMap': c.connectsToMap,
          if (c.connectsToNode != null) 'connectsToNode': c.connectsToNode,
        }).toList(),
      };
      nodes['_editorData'] = editorData;

      // JSON文字列の生成 (圧縮のためインデントなし)
      final json = const JsonEncoder().convert(nodes);
      
      // Webブラウザでのファイルダウンロード処理
      final bytes = utf8.encode(json);
      final blob = html.Blob([bytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..style.display = 'none'
        ..download = 'map_data.json';
        
      html.document.body?.children.add(anchor);
      anchor.click();
      anchor.remove();
      html.Url.revokeObjectUrl(url);

      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('map_data.json のダウンロードが完了しました。ブラウザの「ダウンロード」フォルダをご確認ください。'), duration: Duration(seconds: 4)));
      }
    });
  }
}