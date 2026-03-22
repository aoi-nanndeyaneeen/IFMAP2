import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'config.dart';

class MapPainter extends CustomPainter {
  final Map<String, dynamic> nodes;
  final List<dynamic> cells;
  final List<dynamic> rooms;
  final List<String> path;
  final String? startNode;
  final String? goalNode;
  final String currentLabel;
  final Offset? goalCenter;
  final Offset? startCenter;
  final Offset? estimatedPosition;
  final double? headingDeg;
  final bool showUserDot;
  final bool isGoalOnCurrentFloor;
  final bool isStartOnCurrentFloor;

  MapPainter({
    required this.nodes,
    required this.cells,
    required this.rooms,
    required this.path,
    this.startNode,
    this.goalNode,
    this.goalCenter,
    this.startCenter,
    required this.currentLabel,
    this.estimatedPosition,
    this.headingDeg,
    required this.showUserDot,
    this.isGoalOnCurrentFloor = false,
    this.isStartOnCurrentFloor = false,
  });

  static final Map<String, Picture> _pictureCache = {};
  static String? _cachedLabel;

  @override
  void paint(Canvas canvas, Size size) {
    _drawStaticBackground(canvas, size);
    _drawDynamicElements(canvas, size);
  }

  void _drawStaticBackground(Canvas canvas, Size size) {
    final cacheKey = '${currentLabel}_${size.width}x${size.height}';
    if (_pictureCache.containsKey(cacheKey) && _cachedLabel == currentLabel) {
      canvas.drawPicture(_pictureCache[cacheKey]!);
      return;
    }

    final recorder = PictureRecorder();
    final offscreenCanvas = Canvas(recorder);

    // 1. 背景色 (全体は薄いグレー、屋外はセルごとの色で表現)
    offscreenCanvas.drawRect(
      const Rect.fromLTWH(-5000, -5000, 10000, 10000),
      Paint()..color = Colors.grey.shade100,
    );

    // 2. グリッド
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (double x = 0; x <= AppConfig.mapCanvasSize; x += 10) {
      offscreenCanvas.drawLine(
          Offset(x, 0), Offset(x, AppConfig.mapCanvasSize), gridPaint);
    }
    for (double y = 0; y <= AppConfig.mapCanvasSize; y += 10) {
      offscreenCanvas.drawLine(
          Offset(0, y), Offset(AppConfig.mapCanvasSize, y), gridPaint);
    }

    // 3. セル
    final tilePaint = Paint();
    for (final c in cells) {
      if (c is! Map) continue;
      final type = c['type'] as int? ?? 0;
      if (type == 0) continue;

      final x = (c['x'] as num).toDouble() * AppConfig.pxPerCell;
      final y = (c['y'] as num).toDouble() * AppConfig.pxPerCell;

      tilePaint.color = _getColorForType(type, currentLabel);
      offscreenCanvas.drawRect(Rect.fromLTWH(x, y, 10, 10), tilePaint);
    }

    // 4. 教会（壁・扉）
    for (final id in nodes.keys) {
      final n = nodes[id];
      if (n is! Map) continue;
      _drawBorders(offscreenCanvas, n);
    }

    // 5. 部屋名
    for (final r in rooms) {
      if (r is! Map) continue;
      final name = r['name'] as String?;
      final cx = (r['centerX'] as num?)?.toDouble();
      final cy = (r['centerY'] as num?)?.toDouble();
      if (name != null && cx != null && cy != null) {
        _drawText(offscreenCanvas, name, Offset(cx, cy));
      }
    }

    final picture = recorder.endRecording();
    _pictureCache[cacheKey] = picture;
    _cachedLabel = currentLabel;
    canvas.drawPicture(picture);
  }

  void _drawDynamicElements(Canvas canvas, Size size) {
    // ── ルートライン ─────────────────────────────────────────────
    if (path.isNotEmpty) {
      // 描画パス（ゴールノード手前で止める既存ロジックを維持）
      List<String> drawPath = List.from(path);
      if (drawPath.length > 1 &&
          goalNode != null &&
          drawPath.last == _findNodePosId(goalNode!)) {
        drawPath.removeLast();
      }

      // ★ 出発点: startCenter があればそこから、なければ最初のノード中心
      Offset? lineStart;
      if (isStartOnCurrentFloor && startCenter != null) {
        lineStart = startCenter;
      } else if (drawPath.isNotEmpty) {
        final n = nodes[drawPath.first];
        if (n is Map) {
          lineStart = Offset(
            (n['x'] as num).toDouble() + 5.0,
            (n['y'] as num).toDouble() + 5.0,
          );
        }
      }

      // ★ 終着点: goalCenter があればそこまで、なければ最後のノード中心
      Offset? lineEnd;
      if (isGoalOnCurrentFloor && goalCenter != null) {
        lineEnd = goalCenter;
      } else if (drawPath.isNotEmpty) {
        final n = nodes[drawPath.last];
        if (n is Map) {
          lineEnd = Offset(
            (n['x'] as num).toDouble() + 5.0,
            (n['y'] as num).toDouble() + 5.0,
          );
        }
      }

      final routePath = Path();
      bool first = true;

      // startCenter → 最初のノードへの補助線
      if (lineStart != null && drawPath.isNotEmpty) {
        final firstNode = nodes[drawPath.first];
        if (firstNode is Map) {
          final fx = (firstNode['x'] as num).toDouble() + 5.0;
          final fy = (firstNode['y'] as num).toDouble() + 5.0;
          final firstNodeOffset = Offset(fx, fy);
          if ((lineStart - firstNodeOffset).distance > 1.0) {
            routePath.moveTo(lineStart.dx, lineStart.dy);
            routePath.lineTo(firstNodeOffset.dx, firstNodeOffset.dy);
            first = false;
          }
        }
      }

      // ノード間のメインルートライン
      for (final id in drawPath) {
        final n = nodes[id];
        if (n is! Map) continue;
        final x = (n['x'] as num).toDouble() + 5.0;
        final y = (n['y'] as num).toDouble() + 5.0;
        if (first) {
          routePath.moveTo(x, y);
          first = false;
        } else {
          routePath.lineTo(x, y);
        }
      }

      // 最後のノード → goalCenter への補助線
      if (lineEnd != null && drawPath.isNotEmpty) {
        final lastNode = nodes[drawPath.last];
        if (lastNode is Map) {
          final lx = (lastNode['x'] as num).toDouble() + 5.0;
          final ly = (lastNode['y'] as num).toDouble() + 5.0;
          final lastNodeOffset = Offset(lx, ly);
          if ((lineEnd - lastNodeOffset).distance > 1.0) {
            routePath.lineTo(lineEnd.dx, lineEnd.dy);
          }
        }
      }

      // グロー（背景ぼかし）
      canvas.drawPath(
          routePath,
          Paint()
            ..color = Colors.redAccent.withValues(alpha: 0.3)
            ..strokeWidth = 10
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      // メインライン
      canvas.drawPath(
          routePath,
          Paint()
            ..color = Colors.redAccent
            ..strokeWidth = 4
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round);
    }

    // ── 目的地マーカー ────────────────────────────────────────────
    if (goalNode != null && isGoalOnCurrentFloor) {
      // ★ goalCenter 優先 → なければノード中央(+5)
      final rawPos = goalCenter ?? _findNodePos(goalNode!);
      if (rawPos != null) {
        final markerPos = goalCenter != null
            ? rawPos
            : Offset(rawPos.dx + 5, rawPos.dy + 5);
        _drawMarker(canvas, markerPos, Colors.orange.shade800);
      }
    }

    // ── 出発地マーカー ────────────────────────────────────────────
    if (startNode != null && isStartOnCurrentFloor) {
      // ★ startCenter 優先 → なければノード中央(+5)
      final rawPos = startCenter ?? _findNodePos(startNode!);
      if (rawPos != null) {
        final markerPos = startCenter != null
            ? rawPos
            : Offset(rawPos.dx + 5, rawPos.dy + 5);
        _drawMarker(canvas, markerPos, Colors.cyan.shade600);
      }
    }

    // ── 現在地ドット ──────────────────────────────────────────────
    if (estimatedPosition != null && showUserDot) {
      final p = Offset(estimatedPosition!.dx + 5, estimatedPosition!.dy + 5);
      canvas.drawCircle(p, 9, Paint()..color = Colors.white);
      canvas.drawCircle(p, 7, Paint()..color = Colors.blue.shade600);
      if (headingDeg != null) _drawHeading(canvas, p, headingDeg!);
    }
  }


  void _drawText(Canvas canvas, String text, Offset center) {
    const style = TextStyle(
        color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold);
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas,
        Offset(center.dx - painter.width / 2, center.dy - painter.height / 2));
  }

  void _drawMarker(Canvas canvas, Offset p, Color color) {
    canvas.drawCircle(p, 8, Paint()..color = Colors.white);
    canvas.drawCircle(p, 6, Paint()..color = color);
  }

  void _drawHeading(Canvas canvas, Offset p, double deg) {
    final rad = deg * pi / 180;
    final path = Path();
    path.moveTo(p.dx + 12 * cos(rad), p.dy + 12 * sin(rad));
    path.lineTo(p.dx + 6 * cos(rad + 2.5), p.dy + 6 * sin(rad + 2.5));
    path.lineTo(p.dx + 6 * cos(rad - 2.5), p.dy + 6 * sin(rad - 2.5));
    path.close();
    canvas.drawPath(path, Paint()..color = Colors.blue.shade700);
  }

  String? _findNodePosId(String idOrName) {
    if (nodes.containsKey(idOrName)) return idOrName;
    for (final e in nodes.entries) {
      if (e.value is Map && e.value['name'] == idOrName) return e.key;
    }
    return null;
  }

  Offset? _findNodePos(String idOrName) {
    final id = _findNodePosId(idOrName);
    if (id != null) {
      final n = nodes[id];
      return Offset((n['x'] as num).toDouble(), (n['y'] as num).toDouble());
    }
    return null;
  }

  void _drawBorders(Canvas canvas, Map n) {
    final x = (n['x'] as num).toDouble();
    final y = (n['y'] as num).toDouble();
    final wallPaint = Paint()
      ..color = Colors.red.shade900
      ..strokeWidth = 2;
    final doorPaint = Paint()
      ..color = Colors.orange.shade800
      ..strokeWidth = 4;

    if (n['wallTop'] == true)
      canvas.drawLine(Offset(x, y), Offset(x + 10, y), wallPaint);
    if (n['wallBottom'] == true)
      canvas.drawLine(Offset(x, y + 10), Offset(x + 10, y + 10), wallPaint);
    if (n['wallLeft'] == true)
      canvas.drawLine(Offset(x, y), Offset(x, y + 10), wallPaint);
    if (n['wallRight'] == true)
      canvas.drawLine(Offset(x + 10, y), Offset(x + 10, y + 10), wallPaint);

    if (n['doorTop'] == true)
      canvas.drawLine(Offset(x + 2, y), Offset(x + 8, y), doorPaint);
    if (n['doorBottom'] == true)
      canvas.drawLine(Offset(x + 2, y + 10), Offset(x + 8, y + 10), doorPaint);
    if (n['doorLeft'] == true)
      canvas.drawLine(Offset(x, y + 2), Offset(x, y + 8), doorPaint);
    if (n['doorRight'] == true)
      canvas.drawLine(Offset(x + 10, y + 2), Offset(x + 10, y + 8), doorPaint);
  }

  Color _getColorForType(int type, String floor) {
    switch (type) {
      case 1:
        return Colors.white;
      case 3:
        return Colors.orange.shade50; // ちょっと見やすく
      case 4:
        return Colors.brown.shade100;
      case 5:
        return Colors.purple.shade100;
      case 6:
        return floor.contains('1F') ? Colors.lightGreen.shade200 : Colors.white;
      default:
        return Colors.transparent;
    }
  }

  @override
  bool shouldRepaint(MapPainter oldDelegate) {
    return oldDelegate.currentLabel != currentLabel ||
        oldDelegate.path != path ||
        oldDelegate.goalNode != goalNode ||
        oldDelegate.estimatedPosition != estimatedPosition ||
        oldDelegate.showUserDot != showUserDot ||
        oldDelegate.headingDeg != headingDeg;
  }
}
