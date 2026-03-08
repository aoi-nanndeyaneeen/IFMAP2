import 'dart:math'; // ← 矢印の角度計算のために追加
import 'package:flutter/material.dart';

class MapPainter extends CustomPainter {
  final Map<String, dynamic> nodes;
  final String? startNode;
  final String? goalNode;
  final List<String> path;

  MapPainter({
    required this.nodes,
    required this.startNode,
    required this.goalNode,
    required this.path,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final nodePaint = Paint()..color = Colors.grey..style = PaintingStyle.fill;
    final startPaint = Paint()..color = Colors.red..style = PaintingStyle.fill;
    final goalPaint = Paint()..color = Colors.blue..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..color = Colors.green
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round // ← 線の端を丸くして綺麗にする
      ..strokeJoin = StrokeJoin.round // ← 折れ曲がりを綺麗にする
      ..style = PaintingStyle.stroke;

    // 1. ルートの線と矢印を引く
    if (path.length > 1) {
      for (int i = 0; i < path.length - 1; i++) {
        final p1 = Offset(nodes[path[i]]['x'].toDouble(), nodes[path[i]]['y'].toDouble());
        final p2 = Offset(nodes[path[i+1]]['x'].toDouble(), nodes[path[i+1]]['y'].toDouble());
        
        // メインの線を引く
        canvas.drawLine(p1, p2, linePaint);

        // === 矢印（V字）の描画処理 ===
        // 線分の中間点を計算（ここに矢印を置く）
        final midPoint = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
        
        // p1からp2への角度を計算
        final angle = atan2(p2.dy - p1.dy, p2.dx - p1.dx);
        
        // 矢印の傘の長さと広がり具合（角度）
        const arrowLength = 15.0;
        const arrowAngle = pi / 6; // 30度

        // 傘の左側の点
        final p3 = Offset(
          midPoint.dx - arrowLength * cos(angle - arrowAngle),
          midPoint.dy - arrowLength * sin(angle - arrowAngle),
        );
        // 傘の右側の点
        final p4 = Offset(
          midPoint.dx - arrowLength * cos(angle + arrowAngle),
          midPoint.dy - arrowLength * sin(angle + arrowAngle),
        );

        // V字を描画
        canvas.drawLine(midPoint, p3, linePaint);
        canvas.drawLine(midPoint, p4, linePaint);
      }
    }

    // 2. ノードの丸を描く
    nodes.forEach((key, value) {
      final offset = Offset(value['x'].toDouble(), value['y'].toDouble());
      
      if (key == startNode) {
        canvas.drawCircle(offset, 10.0, startPaint);
      } else if (key == goalNode) {
        canvas.drawCircle(offset, 10.0, goalPaint);
      } else {
        canvas.drawCircle(offset, 5.0, nodePaint);
      }
    });
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}