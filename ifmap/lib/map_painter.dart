// lib/map_painter.dart
import 'dart:math';
import 'package:flutter/material.dart';

class MapPainter extends CustomPainter {
  final Map<String, dynamic> nodes;
  final List<String> path;
  final String? startNode;
  final String? goalNode;

  MapPainter({required this.nodes, required this.path, this.startNode, this.goalNode});

  @override
  void paint(Canvas canvas, Size size) {
    // ペン設定（背景になる道は極限まで薄く）
    final edgePaint = Paint()..color = Colors.grey.withValues(alpha: 0.15)..strokeWidth = 2;
    
    // ★修正：ルートPaintを完全に不透明（透過なし）の赤に変更、少し細くして矢印を目立たせる
    final pathPaint = Paint()
      ..color = Colors.red // 透過なし
      ..strokeWidth = 4 // 少し細くする（以前は6）
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // 【1層目】すべての道（エッジ）を一番後ろに描画
    for (String nodeId in nodes.keys) {
      final double x1 = (nodes[nodeId]['x'] as num).toDouble();
      final double y1 = (nodes[nodeId]['y'] as num).toDouble();
      for (String targetId in nodes[nodeId]['edges']) {
        if (nodes.containsKey(targetId)) {
          final double x2 = (nodes[targetId]['x'] as num).toDouble();
          final double y2 = (nodes[targetId]['y'] as num).toDouble();
          canvas.drawLine(Offset(x1, y1), Offset(x2, y2), edgePaint);
        }
      }
    }

    // 【2層目】最短ルート（不透明な赤い線）と ★進行方向の赤い矢印★
    for (int i = 0; i < path.length - 1; i++) {
      if (nodes.containsKey(path[i]) && nodes.containsKey(path[i + 1])) {
        final double x1 = (nodes[path[i]]['x'] as num).toDouble();
        final double y1 = (nodes[path[i]]['y'] as num).toDouble();
        // バグ修正：targetId ではなく path[i+1] の座標を取得
        final double x2 = (nodes[path[i + 1]]['x'] as num).toDouble();
        final double y2 = (nodes[path[i + 1]]['y'] as num).toDouble();
        
        // 1. 不透明な赤い線を引く（これが矢印の「軸」になる）
        canvas.drawLine(Offset(x1, y1), Offset(x2, y2), pathPaint);

        // 2. 矢印の描画（不透明な赤い三角形を、線の上に重ねて描く）
        final double dist = sqrt(pow(x2 - x1, 2) + pow(y2 - y1, 2));
        if (dist > 8) { // 距離が短すぎると矢印が潰れるので除外
          // ★修正：三角形のサイズを少し大きくする
          final double arrowSize = 8; 
          final double angle = atan2(y2 - y1, x2 - x1);
          final Offset midPoint = Offset((x1 + x2) / 2, (y1 + y2) / 2);

          final Path arrowPath = Path();
          arrowPath.moveTo(midPoint.dx + arrowSize * cos(angle), midPoint.dy + arrowSize * sin(angle));
          arrowPath.lineTo(midPoint.dx + arrowSize * cos(angle + 4 * pi / 5), midPoint.dy + arrowSize * sin(angle + 4 * pi / 5));
          arrowPath.lineTo(midPoint.dx + arrowSize * cos(angle - 4 * pi / 5), midPoint.dy + arrowSize * sin(angle - 4 * pi / 5));
          arrowPath.close();

          // ★修正：透過なしの赤で三角形を描く。線の上に重なり、一体化して見える。
          canvas.drawPath(arrowPath, Paint()..color = Colors.red); // 透過なし
        }
      }
    }

    // 【3層目】ノードの点と、文字（テキスト）を描画
    for (String nodeId in nodes.keys) {
      final double x = (nodes[nodeId]['x'] as num).toDouble();
      final double y = (nodes[nodeId]['y'] as num).toDouble();

      Paint currentPaint = Paint()..color = Colors.blue.withValues(alpha: 0.2);
      double radius = 3;

      if (nodeId == startNode) {
        currentPaint = Paint()..color = Colors.green; radius = 8;
      } else if (nodeId == goalNode) {
        currentPaint = Paint()..color = Colors.orange; radius = 8;
      } else if (nodes[nodeId]['isStairs'] == true || nodeId == '階段' || nodeId.toLowerCase() == 'stairs') {
        currentPaint = Paint()..color = Colors.purple; radius = 6;
      } else if (!nodeId.startsWith('node_')) {
        currentPaint = Paint()..color = Colors.blueGrey; radius = 4;
      }

      canvas.drawCircle(Offset(x, y), radius, currentPaint);

      // 文字の描画
      if (!nodeId.startsWith('node_') || nodes[nodeId]['isStairs'] == true) {
        String displayName = (nodes[nodeId]['isStairs'] == true || nodeId == '階段' || nodeId.toLowerCase() == 'stairs') ? '階段' : nodeId;
        final textPainter = TextPainter(
          text: TextSpan(text: displayName, style: const TextStyle(color: Colors.black87, fontSize: 11, fontWeight: FontWeight.bold)),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        final bgRect = Rect.fromLTWH(x - textPainter.width / 2 - 2, y + 8, textPainter.width + 4, textPainter.height + 2);
        canvas.drawRect(bgRect, Paint()..color = Colors.white.withValues(alpha: 0.8));
        textPainter.paint(canvas, Offset(x - textPainter.width / 2, y + 9));
      }
    }

    // 【最前面】現在地のポップアップ
    if (startNode != null && nodes.containsKey(startNode)) {
      final double x = (nodes[startNode!]['x'] as num).toDouble();
      final double y = (nodes[startNode!]['y'] as num).toDouble();
      
      final textPainter = TextPainter(
        text: const TextSpan(text: '📍現在地', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      final bgRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x - textPainter.width / 2 - 4, y - 28, textPainter.width + 8, textPainter.height + 4),
        const Radius.circular(4)
      );
      canvas.drawRRect(bgRect, Paint()..color = Colors.blue.shade700); 
      textPainter.paint(canvas, Offset(x - textPainter.width / 2, y - 26));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}