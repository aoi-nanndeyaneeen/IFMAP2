// lib/map_painter.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'config.dart';

class MapPainter extends CustomPainter {
  final Map<String, dynamic> nodes;
  final List<dynamic> cells;
  final List<dynamic> rooms; // 部屋の中心点データ
  final List<String> path;
  final String? startNode;
  final String? goalNode;
  final String currentLabel; // 現在のフロアラベル
  final Offset? estimatedPosition;
  final double? headingDeg; // ★ コンパス方位角（度）

  MapPainter({
    required this.nodes,
    required this.cells,
    required this.rooms,
    required this.path,
    this.startNode,
    this.goalNode,
    required this.currentLabel,
    this.estimatedPosition,
    this.headingDeg,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1Fの表現（ラベルに1Fが含まれる場合）
    if (currentLabel.toUpperCase().contains('1F')) {
      canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFE8F5E9)); // より明確な薄緑
    }

    // 背景のグリッド（プレミアム感の追加）
    _drawGrid(canvas, size);

    // 【0層目】背景セルの描画 (部屋の塗りつぶしと壁)
    _drawCells(canvas);

    final edgePaint = Paint()
      ..color = Colors.blueGrey.withValues(alpha: 0.1)
      ..strokeWidth = 1.5;
    
    final pathPaint = Paint()
      ..color = Colors.redAccent
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // シャドウ効果用のペイント
    final pathShadowPaint = Paint()
      ..color = Colors.redAccent.withValues(alpha: 0.3)
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    // 【1層目】すべての道（背景として薄く）
    for (String nId in nodes.keys) {
      if (nodes[nId] is! Map) continue; // メタデータ等をスキップ
      final node = nodes[nId] as Map<String, dynamic>;
      final x1 = (node['x'] as num?)?.toDouble();
      final y1 = (node['y'] as num?)?.toDouble();
      if (x1 == null || y1 == null) continue;

      for (String tId in node['edges'] ?? []) {
        final target = nodes[tId];
        if (target is Map<String, dynamic>) {
          final x2 = (target['x'] as num?)?.toDouble();
          final y2 = (target['y'] as num?)?.toDouble();
          if (x2 != null && y2 != null) {
            canvas.drawLine(Offset(x1, y1), Offset(x2, y2), edgePaint);
          }
        }
      }
    }

    // 【2層目】最短ルート（シャドウ付き）
    if (path.isNotEmpty) {
      final routePath = Path();
      bool first = true;
      for (int i = 0; i < path.length; i++) {
        final node = nodes[path[i]];
        if (node is! Map) continue;
        final x = (node['x'] as num?)?.toDouble();
        final y = (node['y'] as num?)?.toDouble();
        if (x == null || y == null) continue;
        
        final p = Offset(x + 5, y + 5);
        if (first) {
          routePath.moveTo(p.dx, p.dy);
          first = false;
        } else {
          routePath.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(routePath, pathShadowPaint);
      canvas.drawPath(routePath, pathPaint);

      // 進行方向の矢印
      for (int i = 0; i < path.length - 1; i++) {
        final p1 = nodes[path[i]];
        final p2 = nodes[path[i+1]];
        if (p1 is! Map || p2 is! Map) continue;
        
        final x1 = (p1['x'] as num?)?.toDouble();
        final y1 = (p1['y'] as num?)?.toDouble();
        final x2 = (p2['x'] as num?)?.toDouble();
        final y2 = (p2['y'] as num?)?.toDouble();
        
        if (x1 != null && y1 != null && x2 != null && y2 != null) {
          _drawArrow(canvas, Offset(x1 + 5, y1 + 5), Offset(x2 + 5, y2 + 5));
        }
      }
    }

    // 【3層目】ノード
    final List<String> specialNodes = []; // スタート、ゴール、階段

    for (String nId in nodes.keys) {
      final node = nodes[nId];
      if (node is! Map) continue;
      
      if (nId == startNode || nId == goalNode || node['isStairs'] == true) {
        specialNodes.add(nId);
      } else {
        final x = (node['x'] as num?)?.toDouble();
        final y = (node['y'] as num?)?.toDouble();
        if (x != null && y != null) {
          canvas.drawCircle(Offset(x + 5, y + 5), 1.5, Paint()..color = Colors.blueGrey.withValues(alpha: 0.2));
        }
      }
    }

    // 部屋ラベルの描画 (事前計算された中心点を使用)
    for (final room in rooms) {
      if (room is Map) {
        final name = room['name'] as String?;
        final cx = (room['centerX'] as num?)?.toDouble();
        final cy = (room['centerY'] as num?)?.toDouble();
        if (name != null && cx != null && cy != null) {
          _drawLabel(canvas, name, Offset(cx, cy), Colors.indigo.shade800, Colors.indigo.shade50);
        }
      }
    }

    // 特別なノードの描画 (アイコン類)
    for (String nId in specialNodes) {
      final node = nodes[nId];
      if (node is! Map) continue;
      final x = (node['x'] as num?)?.toDouble();
      final y = (node['y'] as num?)?.toDouble();
      if (x == null || y == null) continue;
      final pos = Offset(x + 5, y + 5); 

      if (nId == startNode || node['name'] == startNode) {
        _drawMarker(canvas, pos, Colors.green);
        _drawBadge(canvas, '出発地', Offset(pos.dx, pos.dy - 35), Colors.green.shade700);
      } else if (nId == goalNode || node['name'] == goalNode) {
        _drawMarker(canvas, pos, Colors.orange);
        _drawBadge(canvas, '目的地', Offset(pos.dx, pos.dy - 35), Colors.orange.shade700);
      } else if (node['isStairs'] == true) {
        _drawMarker(canvas, pos, Colors.purple);
        _drawLabel(canvas, '階段', pos, Colors.purple.shade800, Colors.purple.shade50);
      }
    }

    // 【5層目】推定現在地
    if (estimatedPosition != null) {
      final p = estimatedPosition!;
      _drawPulse(canvas, p, Colors.cyan);

      if (headingDeg != null) {
        final mapAngle = (headingDeg! - AppConfig.mapNorthDegrees + 360) % 360;
        final cAngle = mapAngle * pi / 180 - pi / 2;
        final cone = Path()
          ..moveTo(p.dx, p.dy)
          ..arcTo(Rect.fromCircle(center: p, radius: 60), cAngle - pi/6, pi/3, false)
          ..close();
        canvas.drawPath(cone, Paint()..shader = RadialGradient(
          colors: [Colors.cyan.withValues(alpha: 0.4), Colors.cyan.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: p, radius: 60)));
      }

      canvas.drawCircle(p, 8, Paint()..color = Colors.white);
      canvas.drawCircle(p, 6, Paint()..color = Colors.cyan.shade600);
    }
  }

  void _drawCells(Canvas canvas) {
    final cellW = 10.0; // 本来はAppConfig.pxPerCellだが、一旦固定(editor側と一致)
    final cellH = 10.0;

    final wallPaint = Paint()
      ..color = Colors.blueGrey.shade800
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.square;

    final doorPaint = Paint()
      ..color = Colors.orange.shade400
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.butt;

    for (var c in cells) {
      if (c is! Map) continue;
      final x = (c['x'] as num).toDouble() * cellW;
      final y = (c['y'] as num).toDouble() * cellH;
      final type = c['type'] as int? ?? 0;
      final name = c['name'] as String?;

      // 1. セルの背景色
      Color? bgColor;
      if (type == 1) bgColor = Colors.blueGrey.shade50; // 通路
      if (type == 3 || name != null) bgColor = Colors.indigo.shade50; // 目的地/部屋
      if (type == 4) bgColor = Colors.green.shade50; // 階段
      if (type == 5) bgColor = Colors.deepPurple.shade50; // 接続点

      if (bgColor != null) {
        canvas.drawRect(Rect.fromLTWH(x, y, cellW, cellH), Paint()..color = bgColor);
      }

      // 2. 壁の描画
      if (c['wallTop'] == true)    canvas.drawLine(Offset(x, y), Offset(x + cellW, y), wallPaint);
      if (c['wallBottom'] == true) canvas.drawLine(Offset(x, y + cellH), Offset(x + cellW, y + cellH), wallPaint);
      if (c['wallLeft'] == true)   canvas.drawLine(Offset(x, y), Offset(x, y + cellH), wallPaint);
      if (c['wallRight'] == true)  canvas.drawLine(Offset(x + cellW, y), Offset(x + cellW, y + cellH), wallPaint);

      // 3. 扉の描画 (より太く、茶色系で表現)
      final doorPaint = Paint()
        ..color = Colors.brown.shade400
        ..strokeWidth = 4.0
        ..strokeCap = StrokeCap.round;

      if (c['doorTop'] == true)    canvas.drawLine(Offset(x + 2, y), Offset(x + cellW - 2, y), doorPaint);
      if (c['doorBottom'] == true) canvas.drawLine(Offset(x + 2, y + cellH), Offset(x + cellW - 2, y + cellH), doorPaint);
      if (c['doorLeft'] == true)   canvas.drawLine(Offset(x, y + 2), Offset(x, y + cellH - 2), doorPaint);
      if (c['doorRight'] == true)  canvas.drawLine(Offset(x + cellW, y + 2), Offset(x + cellW, y + cellH - 2), doorPaint);
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()..color = Colors.grey.withValues(alpha: 0.05)..strokeWidth = 1;
    for (double x = 0; x <= size.width; x += 50) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y <= size.height; y += 50) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  void _drawArrow(Canvas canvas, Offset p1, Offset p2) {
    final dist = (p2 - p1).distance;
    if (dist < 20) return;
    final angle = (p2 - p1).direction;
    final mid = (p1 + p2) / 2;
    const arrowSize = 6.0;
    final path = Path()
      ..moveTo(mid.dx + arrowSize * cos(angle), mid.dy + arrowSize * sin(angle))
      ..lineTo(mid.dx + arrowSize * cos(angle + 2.5), mid.dy + arrowSize * sin(angle + 2.5))
      ..lineTo(mid.dx + arrowSize * cos(angle - 2.5), mid.dy + arrowSize * sin(angle - 2.5))
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.redAccent);
  }

  void _drawMarker(Canvas canvas, Offset pos, Color color) {
    canvas.drawCircle(pos, 10, Paint()..color = Colors.white..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
    canvas.drawCircle(pos, 8, Paint()..color = color);
  }

  void _drawPulse(Canvas canvas, Offset pos, Color color) {
    canvas.drawCircle(pos, 20, Paint()..color = color.withValues(alpha: 0.2));
  }

  void _drawLabel(Canvas canvas, String text, Offset pos, Color textColor, Color bgColor) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: textColor, fontSize: 10, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    
    final rect = Rect.fromCenter(center: pos, width: tp.width + 10, height: tp.height + 4);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(10)), Paint()..color = bgColor);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(10)), Paint()..color = textColor.withValues(alpha: 0.2)..style = PaintingStyle.stroke..strokeWidth = 1);
    
    tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy - tp.height / 2));
  }

  void _drawBadge(Canvas canvas, String text, Offset pos, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    
    final rect = Rect.fromCenter(center: pos, width: tp.width + 12, height: tp.height + 6);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)), Paint()..color = color);
    
    final tail = Path()
      ..moveTo(pos.dx - 4, pos.dy + tp.height / 2 + 3)
      ..lineTo(pos.dx + 4, pos.dy + tp.height / 2 + 3)
      ..lineTo(pos.dx, pos.dy + tp.height / 2 + 8)
      ..close();
    canvas.drawPath(tail, Paint()..color = color);

    tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant MapPainter old) => true;
}