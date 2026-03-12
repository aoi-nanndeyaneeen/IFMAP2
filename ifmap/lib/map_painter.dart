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
    final edgePaint = Paint()..color = Colors.grey.withValues(alpha: 0.4)..strokeWidth = 2;
    final pathPaint = Paint()
      ..color = Colors.redAccent..strokeWidth = 4
      ..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;

    // 【1層目】すべての道
    for (String nId in nodes.keys) {
      final x1 = (nodes[nId]['x'] as num).toDouble();
      final y1 = (nodes[nId]['y'] as num).toDouble();
      for (String tId in nodes[nId]['edges']) {
        if (nodes.containsKey(tId)) {
          canvas.drawLine(Offset(x1, y1),
              Offset((nodes[tId]['x'] as num).toDouble(), (nodes[tId]['y'] as num).toDouble()), edgePaint);
        }
      }
    }

    // 【2層目】最短ルートと矢印
    for (int i = 0; i < path.length - 1; i++) {
      if (!nodes.containsKey(path[i]) || !nodes.containsKey(path[i + 1])) continue;
      final x1 = (nodes[path[i]]['x'] as num).toDouble();
      final y1 = (nodes[path[i]]['y'] as num).toDouble();
      final x2 = (nodes[path[i + 1]]['x'] as num).toDouble();
      final y2 = (nodes[path[i + 1]]['y'] as num).toDouble();
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), pathPaint);

      final dist = sqrt(pow(x2 - x1, 2) + pow(y2 - y1, 2));
      if (dist > 8) {
        const arrowSize = 8.0;
        final angle = atan2(y2 - y1, x2 - x1);
        final mid = Offset((x1 + x2) / 2, (y1 + y2) / 2);
        final ap = Path()
          ..moveTo(mid.dx + arrowSize * cos(angle), mid.dy + arrowSize * sin(angle))
          ..lineTo(mid.dx + arrowSize * cos(angle + 4 * pi / 5), mid.dy + arrowSize * sin(angle + 4 * pi / 5))
          ..lineTo(mid.dx + arrowSize * cos(angle - 4 * pi / 5), mid.dy + arrowSize * sin(angle - 4 * pi / 5))
          ..close();
        canvas.drawPath(ap, Paint()..color = Colors.redAccent);
      }
    }

    // 【3層目】ノード点とラベル
    for (String nId in nodes.keys) {
      final x = (nodes[nId]['x'] as num).toDouble();
      final y = (nodes[nId]['y'] as num).toDouble();
      Paint pt = Paint()..color = Colors.blueGrey.withValues(alpha: 0.6);
      double r = 3;
      if (nId == startNode)                                        { pt = Paint()..color = Colors.green;   r = 8; }
      else if (nId == goalNode)                                    { pt = Paint()..color = Colors.orange;  r = 8; }
      else if (nodes[nId]['isStairs'] == true || nId.toLowerCase() == 'stairs') { pt = Paint()..color = Colors.purple; r = 6; }
      else if (!nId.startsWith('node_'))                          { pt = Paint()..color = Colors.indigo; r = 4; }
      canvas.drawCircle(Offset(x, y), r, pt);
      if (!nId.startsWith('node_') || nodes[nId]['isStairs'] == true) {
        final label = (nodes[nId]['isStairs'] == true || nId.toLowerCase() == 'stairs') ? '階段' : nId;
        _drawLabel(canvas, label, Offset(x, y + 9), Colors.black87);
      }
    }

    // 【4層目】QR確定地点バッジ
    if (startNode != null && nodes.containsKey(startNode)) {
      final x = (nodes[startNode!]['x'] as num).toDouble();
      final y = (nodes[startNode!]['y'] as num).toDouble();
      _drawBadge(canvas, '📍QR確定地点', Offset(x, y - 28), Colors.blue.shade700);
    }

    // 【5層目】推定現在地 + ★方位コーン
    if (estimatedPosition != null) {
      final p = estimatedPosition!;

      // 方位コーン（headingDeg が取得できている場合のみ）
      if (headingDeg != null) {
        final mapAngle  = (headingDeg! - AppConfig.mapNorthDegrees + 360) % 360;
        final cAngle    = mapAngle * pi / 180 - pi / 2; // キャンバス角に変換
        const coneR     = 50.0;
        const coneHalf  = pi / 6; // ±30度 の扇形
        final cone = Path()
          ..moveTo(p.dx, p.dy)
          ..arcTo(Rect.fromCircle(center: p, radius: coneR),
              cAngle - coneHalf, coneHalf * 2, false)
          ..close();
        canvas.drawPath(cone, Paint()..color = Colors.cyan.withValues(alpha: 0.25));
      }

      // 外輪（透過）+ 内円（不透明）
      canvas.drawCircle(p, 14, Paint()..color = Colors.cyan.withValues(alpha: 0.25));
      canvas.drawCircle(p, 8, Paint()..color = Colors.cyan.shade600);
      _drawBadge(canvas, '🚶現在地（推定）', Offset(p.dx, p.dy - 28), Colors.cyan.shade700);
    }
  }

  void _drawLabel(Canvas canvas, String text, Offset pos, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.drawRect(
      Rect.fromLTWH(pos.dx - tp.width / 2 - 2, pos.dy, tp.width + 4, tp.height + 2),
      Paint()..color = Colors.white.withValues(alpha: 0.8),
    );
    tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy));
  }

  void _drawBadge(Canvas canvas, String text, Offset pos, Color bgColor) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(pos.dx - tp.width / 2 - 4, pos.dy, tp.width + 8, tp.height + 4), const Radius.circular(4)),
      Paint()..color = bgColor,
    );
    tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy + 2));
  }

  @override
  bool shouldRepaint(covariant MapPainter old) =>
      old.estimatedPosition != estimatedPosition || old.headingDeg != headingDeg ||
      old.path != path || old.startNode != startNode;
}