// lib/map_painter.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'config.dart';

class MapPainter extends CustomPainter {
  final Map<String, dynamic> nodes;
  final List<String> path;
  final String? startNode;
  final String? goalNode;
  final Offset? estimatedPosition;
  final double? headingDeg; // ★ コンパス方位角（度）

  MapPainter({
    required this.nodes,
    required this.path,
    this.startNode,
    this.goalNode,
    this.estimatedPosition,
    this.headingDeg,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 背景のグリッド（プレミアム感の追加）
    _drawGrid(canvas, size);

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
      if (nId == '_editorData') continue;
      final x1 = (nodes[nId]['x'] as num).toDouble();
      final y1 = (nodes[nId]['y'] as num).toDouble();
      for (String tId in nodes[nId]['edges']) {
        if (nodes.containsKey(tId)) {
          canvas.drawLine(
            Offset(x1, y1),
            Offset((nodes[tId]['x'] as num).toDouble(), (nodes[tId]['y'] as num).toDouble()),
            edgePaint,
          );
        }
      }
    }

    // 【2層目】最短ルート（シャドウ付き）
    if (path.isNotEmpty) {
      final routePath = Path();
      bool first = true;
      for (int i = 0; i < path.length; i++) {
        if (!nodes.containsKey(path[i])) continue;
        final p = Offset((nodes[path[i]]['x'] as num).toDouble(), (nodes[path[i]]['y'] as num).toDouble());
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
        if (!nodes.containsKey(path[i]) || !nodes.containsKey(path[i+1])) continue;
        final p1 = Offset((nodes[path[i]]['x'] as num).toDouble(), (nodes[path[i]]['y'] as num).toDouble());
        final p2 = Offset((nodes[path[i+1]]['x'] as num).toDouble(), (nodes[path[i+1]]['y'] as num).toDouble());
        _drawArrow(canvas, p1, p2);
      }
    }

    // 【3層目】ノードとラベル
    final List<String> roomNodes = [];
    final List<String> specialNodes = []; // スタート、ゴール、階段

    for (String nId in nodes.keys) {
      if (nId == '_editorData') continue;
      if (nId == startNode || nId == goalNode || nodes[nId]['isStairs'] == true) {
        specialNodes.add(nId);
      } else if (!nId.startsWith('node_')) {
        roomNodes.add(nId);
      } else {
        canvas.drawCircle(
          Offset((nodes[nId]['x'] as num).toDouble(), (nodes[nId]['y'] as num).toDouble()),
          1.5,
          Paint()..color = Colors.blueGrey.withValues(alpha: 0.2),
        );
      }
    }

    // 部屋ラベルの描画
    for (String nId in roomNodes) {
      final pos = Offset((nodes[nId]['x'] as num).toDouble(), (nodes[nId]['y'] as num).toDouble());
      _drawLabel(canvas, nId, pos, Colors.indigo.shade800, Colors.indigo.shade50);
    }

    // 特別なノードの描画
    for (String nId in specialNodes) {
      final pos = Offset((nodes[nId]['x'] as num).toDouble(), (nodes[nId]['y'] as num).toDouble());
      if (nId == startNode) {
        _drawMarker(canvas, pos, Colors.green);
        _drawBadge(canvas, '出発地', Offset(pos.dx, pos.dy - 35), Colors.green.shade700);
      } else if (nId == goalNode) {
        _drawMarker(canvas, pos, Colors.orange);
        _drawBadge(canvas, '目的地', Offset(pos.dx, pos.dy - 35), Colors.orange.shade700);
      } else if (nodes[nId]['isStairs'] == true) {
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
    
    final rect = Rect.fromCenter(center: Offset(pos.dx, pos.dy + 15), width: tp.width + 10, height: tp.height + 4);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(10)), Paint()..color = bgColor);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(10)), Paint()..color = textColor.withValues(alpha: 0.2)..style = PaintingStyle.stroke..strokeWidth = 1);
    
    tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy + 15 - tp.height / 2));
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