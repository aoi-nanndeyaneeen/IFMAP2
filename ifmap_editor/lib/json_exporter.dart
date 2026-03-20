import 'dart:convert';
import 'dart:typed_data';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'config.dart';
import 'map_cell.dart';

class JsonExporter {
  static void export(
    BuildContext context,
    List<List<MapCell>> grid,
    Uint8List? bgImageBytes,
    String fileName,
  ) {
    try {
      if (grid.isEmpty || grid[0].isEmpty) {
        return;
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラーが発生しました: $e')));
      }
      return;
    }
    
    // UIをブロックしないように、少し処理を遅延させます
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('JSONの生成とダウンロードを準備中です...')));

    Future.microtask(() {
      final nodes = <String, dynamic>{};
      for (int y = 0; y < AppConfig.rows; y++) {
        for (int x = 0; x < AppConfig.cols; x++) {
          final cell = grid[y][x];
          // isWalkableに type 6(屋外)も含まれる。空白(type 0)は絶対に含めない。
          if (!cell.isWalkable) continue;

          final id    = 'node_$y-$x';
          final edges = <String>[];

          final dirs = [
            [-1, 0, 'top'],
            [1, 0, 'bottom'],
            [0, -1, 'left'],
            [0, 1, 'right']
          ];
          for (final d in dirs) {
            final dy = d[0] as int, dx = d[1] as int, dir = d[2] as String;
            final ny = y + dy, nx = x + dx;

            // 横方向: 屋外ノード同士または屋外↔建物は壁チェックをスキップ（両端に壁ない）
            bool isOutdoorCell = cell.type == 6;
            bool canPassA = isOutdoorCell ? true : (!cell.isWall(dir) || cell.isDoor(dir));
            if (!canPassA) continue;

            if (ny >= 0 && ny < AppConfig.rows && nx >= 0 && nx < AppConfig.cols) {
              final nCell = grid[ny][nx];
              if (!nCell.isWalkable) continue;
              bool isNeighborOutdoor = nCell.type == 6;
              // 隣接ノードが屋外マスなら壁チェック不要（屋外に増壁ない）
              bool canPassB = isNeighborOutdoor ? true : (!nCell.isWall(_opposite(dir)) || nCell.isDoor(_opposite(dir)));
              if (!canPassB) continue;
              edges.add('node_$ny-$nx');
            }
          }

          nodes[id] = {
            'x': x * AppConfig.pxPerCell,
            'y': y * AppConfig.pxPerCell,
            'edges': edges,
            if (cell.name != null) 'name': cell.name,
            if (cell.type == 4) 'isStairs':   true,
            if (cell.type == 5) 'isConnector': true,
            if (cell.type == 6) 'isOutdoor':   true,
            if (cell.type == 5 && cell.connectsToMap  != null) 'connectsToMap':  cell.connectsToMap,
            if (cell.type == 5 && cell.connectsToNode != null) 'connectsToNode': cell.connectsToNode,
            if (cell.doorTop) 'doorTop': true,
            if (cell.doorBottom) 'doorBottom': true,
            if (cell.doorLeft) 'doorLeft': true,
            if (cell.doorRight) 'doorRight': true,
          };
        }
      }

      final editorData = {
        'bgImageBase64': bgImageBytes != null ? base64Encode(bgImageBytes!) : null,
        'cells': grid.expand((row) => row).where((c) => c.type != 0 || c.name != null || c.wallTop || c.wallBottom || c.wallLeft || c.wallRight || c.doorTop || c.doorBottom || c.doorLeft || c.doorRight).map((c) => {
          'x': c.x, 'y': c.y, 'type': c.type,
          if (c.name != null) 'name': c.name,
          if (c.connectsToMap != null) 'connectsToMap': c.connectsToMap,
          if (c.connectsToNode != null) 'connectsToNode': c.connectsToNode,
          if (c.wallTop) 'wallTop': true,
          if (c.wallBottom) 'wallBottom': true,
          if (c.wallLeft) 'wallLeft': true,
          if (c.wallRight) 'wallRight': true,
          if (c.doorTop) 'doorTop': true,
          if (c.doorBottom) 'doorBottom': true,
          if (c.doorLeft) 'doorLeft': true,
          if (c.doorRight) 'doorRight': true,
        }).toList(),
      };

      // 部屋の中心点を計算して追加
      final roomCoords = <String, List<Offset>>{};
      for (final row in grid) {
        for (final c in row) {
          final name = c.name;
          if (name != null && name.isNotEmpty) {
            // 部屋(type 3)だけでなく階段(type 4)もラベル対象に含める
            if (c.type == 3 || c.type == 4 || c.isWalkable) {
              roomCoords.putIfAbsent(name, () => []).add(Offset(c.x.toDouble(), c.y.toDouble()));
            }
          }
        }
      }
      final roomSummary = <Map<String, dynamic>>[];
      roomCoords.forEach((name, points) {
        double avgX = points.map((p) => p.dx).reduce((a, b) => a + b) / points.length;
        double avgY = points.map((p) => p.dy).reduce((a, b) => a + b) / points.length;
        roomSummary.add({
          'name': name,
          'centerX': avgX * AppConfig.pxPerCell + (AppConfig.pxPerCell / 2),
          'centerY': avgY * AppConfig.pxPerCell + (AppConfig.pxPerCell / 2),
        });
      });
      editorData['rooms'] = roomSummary;
      
      nodes['_editorData'] = editorData;

      // JSON文字列の生成 (圧縮のためインデントなし)
      final json = const JsonEncoder().convert(nodes);
      
      // Webブラウザでのファイルダウンロード処理
      final bytes = utf8.encode(json);
      final blob = html.Blob([json], 'application/json');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', fileName)
        ..click();
        
      html.document.body?.children.add(anchor);
      anchor.remove();
      html.Url.revokeObjectUrl(url);

      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('map_data.json のダウンロードが完了しました。ブラウザの「ダウンロード」フォルダをご確認ください。'), duration: Duration(seconds: 4)));
      }
    });
  }
 
  static String _opposite(String dir) => switch (dir) {
    'top'    => 'bottom',
    'bottom' => 'top',
    'left'   => 'right',
    'right'  => 'left',
    _        => '',
  };
}