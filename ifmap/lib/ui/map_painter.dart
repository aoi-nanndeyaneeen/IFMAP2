// lib/ui/map_painter.dart
//
// マップの描画。
//
// 描くものは「動かないもの」と「動くもの」に分かれる。
//   動かない … セル・壁・扉・部屋名。フロアを切り替えるまで変わらない。
//   動く     … 経路・出発地/目的地マーカー・現在地ドット・方位の矢印。
// 1フロアに2万マスあるので、動かないほうは Picture に焼いて使い回す。
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../config.dart';
import '../data/map_data.dart';

class MapPainter extends CustomPainter {
  final FloorMap floor;
  final List<String> path;
  final String? startName;
  final String? goalName;
  final Offset? startCenter;
  final Offset? goalCenter;
  final Offset? estimatedPosition;
  final double? headingDeg;
  final bool showUserDot;
  final bool isStartOnCurrentFloor;
  final bool isGoalOnCurrentFloor;

  const MapPainter({
    required this.floor,
    required this.path,
    this.startName,
    this.goalName,
    this.startCenter,
    this.goalCenter,
    this.estimatedPosition,
    this.headingDeg,
    required this.showUserDot,
    this.isStartOnCurrentFloor = false,
    this.isGoalOnCurrentFloor = false,
  });

  // フロアごとの背景キャッシュ。使った順に並べ、古いものから捨てる。
  static final Map<String, ui.Picture> _backgroundCache = {};

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPicture(_background());
    _paintRoute(canvas);
    _paintMarkers(canvas);
    _paintUser(canvas);
  }

  /// テストやフロア構成の変更後にキャッシュを捨てる。
  static void clearCache() {
    for (final p in _backgroundCache.values) {
      p.dispose();
    }
    _backgroundCache.clear();
  }

  ui.Picture _background() {
    final cached = _backgroundCache.remove(floor.label);
    if (cached != null) {
      // 取り出して入れ直すことで「直近に使った」順に並べ替える。
      _backgroundCache[floor.label] = cached;
      return cached;
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    _paintBackground(canvas);
    final picture = recorder.endRecording();

    _backgroundCache[floor.label] = picture;
    while (_backgroundCache.length > AppConfig.backgroundCacheSize) {
      final oldest = _backgroundCache.keys.first;
      _backgroundCache.remove(oldest)?.dispose();
    }
    return picture;
  }

  // ─── 動かないもの ─────────────────────────────────────────────

  void _paintBackground(Canvas canvas) {
    const canvasSize = AppConfig.mapCanvasSize;

    canvas.drawRect(
      const Rect.fromLTWH(0, 0, canvasSize, canvasSize),
      Paint()..color = Colors.grey.shade100,
    );

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (double v = 0; v <= canvasSize; v += AppConfig.pxPerCell) {
      canvas.drawLine(Offset(v, 0), Offset(v, canvasSize), gridPaint);
      canvas.drawLine(Offset(0, v), Offset(canvasSize, v), gridPaint);
    }

    final tilePaint = Paint();
    for (final c in floor.cells) {
      if (c is! Map) continue;
      final type = (c['type'] as num?)?.toInt() ?? CellType.blank;
      if (type == CellType.blank) continue;
      final x = (c['x'] as num).toDouble() * AppConfig.pxPerCell;
      final y = (c['y'] as num).toDouble() * AppConfig.pxPerCell;
      tilePaint.color = _cellColor(c, type);
      canvas.drawRect(
          Rect.fromLTWH(x, y, AppConfig.pxPerCell, AppConfig.pxPerCell), tilePaint);
    }

    for (final n in floor.nodes.values) {
      if (n is Map) _paintBorders(canvas, n);
    }

    // 部屋名。接続点は利用者に見せても意味がないので出さない。
    for (final entry in floor.roomCenters.entries) {
      if (_isConnectorName(entry.key)) continue;
      _paintText(canvas, entry.key, entry.value);
    }
  }

  bool _isConnectorName(String name) {
    final id = floor.entryIdByName[name];
    final node = id == null ? null : floor.nodes[id];
    return node is Map && node['connectsToMap'] != null;
  }

  void _paintBorders(Canvas canvas, Map n) {
    final x = (n['x'] as num).toDouble();
    final y = (n['y'] as num).toDouble();
    const s = AppConfig.pxPerCell;

    final wall = Paint()
      ..color = Colors.red.shade900
      ..strokeWidth = 2;
    final door = Paint()
      ..color = Colors.orange.shade800
      ..strokeWidth = 4;

    if (n['wallTop'] == true) {
      canvas.drawLine(Offset(x, y), Offset(x + s, y), wall);
    }
    if (n['wallBottom'] == true) {
      canvas.drawLine(Offset(x, y + s), Offset(x + s, y + s), wall);
    }
    if (n['wallLeft'] == true) {
      canvas.drawLine(Offset(x, y), Offset(x, y + s), wall);
    }
    if (n['wallRight'] == true) {
      canvas.drawLine(Offset(x + s, y), Offset(x + s, y + s), wall);
    }
    if (n['doorTop'] == true) {
      canvas.drawLine(Offset(x + 2, y), Offset(x + s - 2, y), door);
    }
    if (n['doorBottom'] == true) {
      canvas.drawLine(Offset(x + 2, y + s), Offset(x + s - 2, y + s), door);
    }
    if (n['doorLeft'] == true) {
      canvas.drawLine(Offset(x, y + 2), Offset(x, y + s - 2), door);
    }
    if (n['doorRight'] == true) {
      canvas.drawLine(Offset(x + s, y + 2), Offset(x + s, y + s - 2), door);
    }
  }

  Color _cellColor(Map c, int type) {
    switch (type) {
      case CellType.corridor:
        return Colors.white;
      case CellType.room:
        // エディタと同じ、名前のハッシュから黄色系の色を作る。
        // 隣り合う部屋が別の色になるので境目が見分けられる。
        final name = c['name'] as String?;
        if (name == null || name.isEmpty) {
          return const Color.fromARGB(89, 251, 192, 45);
        }
        final hash = name.hashCode.abs();
        final hue = 35.0 + (hash % 100) / 100.0 * 20.0;
        final sat = 0.6 + ((hash ~/ 100) % 40) / 100.0;
        final lit = 0.45 + ((hash ~/ 10000) % 20) / 100.0;
        return HSLColor.fromAHSL(0.5, hue, sat, lit).toColor();
      case CellType.stairs:
        return Colors.brown.shade100;
      case CellType.connector:
        return Colors.deepPurple.withValues(alpha: 0.45);
      case CellType.outdoor:
        return floor.section.floorLevel == 1
            ? Colors.lightGreen.shade200
            : Colors.white;
      case CellType.decoration:
        return Colors.blueGrey.withValues(alpha: 0.5);
      default:
        return Colors.transparent;
    }
  }

  void _paintText(Canvas canvas, String text, Offset center) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
            color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas,
        Offset(center.dx - painter.width / 2, center.dy - painter.height / 2));
    painter.dispose();
  }

  // ─── 動くもの ─────────────────────────────────────────────────

  void _paintRoute(Canvas canvas) {
    if (path.isEmpty) return;

    // 目的地のノードは部屋の中心まで線を引くので、線としては1つ手前で止める。
    final drawPath = List<String>.from(path);
    if (drawPath.length > 1 &&
        goalName != null &&
        drawPath.last == floor.nodeIdOf(goalName!)) {
      drawPath.removeLast();
    }
    if (drawPath.isEmpty) return;

    final route = Path();
    var started = false;

    // 部屋の中心 → 経路の最初のノード への補助線。
    if (isStartOnCurrentFloor && startCenter != null) {
      final head = _nodeCenter(drawPath.first);
      if (head != null && (startCenter! - head).distance > 1.0) {
        route.moveTo(startCenter!.dx, startCenter!.dy);
        started = true;
      }
    }

    for (final id in drawPath) {
      final p = _nodeCenter(id);
      if (p == null) continue;
      if (started) {
        route.lineTo(p.dx, p.dy);
      } else {
        route.moveTo(p.dx, p.dy);
        started = true;
      }
    }

    // 経路の最後のノード → 部屋の中心 への補助線。
    if (isGoalOnCurrentFloor && goalCenter != null && started) {
      final tail = _nodeCenter(drawPath.last);
      if (tail != null && (goalCenter! - tail).distance > 1.0) {
        route.lineTo(goalCenter!.dx, goalCenter!.dy);
      }
    }
    if (!started) return;

    canvas.drawPath(
      route,
      Paint()
        ..color = Colors.redAccent.withValues(alpha: 0.3)
        ..strokeWidth = 10
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawPath(
      route,
      Paint()
        ..color = Colors.redAccent
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  void _paintMarkers(Canvas canvas) {
    if (goalName != null && isGoalOnCurrentFloor) {
      final p = goalCenter ?? _namedCenter(goalName!);
      if (p != null) _paintMarker(canvas, p, Colors.orange.shade800);
    }
    if (startName != null && isStartOnCurrentFloor) {
      final p = startCenter ?? _namedCenter(startName!);
      if (p != null) _paintMarker(canvas, p, Colors.cyan.shade600);
    }
  }

  void _paintUser(Canvas canvas) {
    final pos = estimatedPosition;
    if (pos == null || !showUserDot) return;
    final p = Offset(pos.dx + AppConfig.cellCenter, pos.dy + AppConfig.cellCenter);
    canvas.drawCircle(p, 9, Paint()..color = Colors.white);
    canvas.drawCircle(p, 7, Paint()..color = Colors.blue.shade600);

    final deg = headingDeg;
    if (deg == null) return;
    final rad = deg * pi / 180;
    final arrow = Path()
      ..moveTo(p.dx + 12 * cos(rad), p.dy + 12 * sin(rad))
      ..lineTo(p.dx + 6 * cos(rad + 2.5), p.dy + 6 * sin(rad + 2.5))
      ..lineTo(p.dx + 6 * cos(rad - 2.5), p.dy + 6 * sin(rad - 2.5))
      ..close();
    canvas.drawPath(arrow, Paint()..color = Colors.blue.shade700);
  }

  void _paintMarker(Canvas canvas, Offset p, Color color) {
    canvas.drawCircle(p, 8, Paint()..color = Colors.white);
    canvas.drawCircle(p, 6, Paint()..color = color);
  }

  Offset? _nodeCenter(String id) {
    final n = floor.nodes[id];
    if (n is! Map) return null;
    return Offset(
      (n['x'] as num).toDouble() + AppConfig.cellCenter,
      (n['y'] as num).toDouble() + AppConfig.cellCenter,
    );
  }

  Offset? _namedCenter(String nameOrId) => floor.centerOf(nameOrId);

  @override
  bool shouldRepaint(MapPainter old) =>
      old.floor != floor ||
      old.path != path ||
      old.startName != startName ||
      old.goalName != goalName ||
      old.startCenter != startCenter ||
      old.goalCenter != goalCenter ||
      old.estimatedPosition != estimatedPosition ||
      old.headingDeg != headingDeg ||
      old.showUserDot != showUserDot ||
      old.isStartOnCurrentFloor != isStartOnCurrentFloor ||
      old.isGoalOnCurrentFloor != isGoalOnCurrentFloor;
}
