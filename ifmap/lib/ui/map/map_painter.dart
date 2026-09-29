// lib/ui/map/map_painter.dart
//
// 地図の描画。
//
// 2つの座標系で描く。
//   地図座標 … 床・部屋・壁・経路。カメラの移動・拡大・回転をかけて描く。
//              線の太さは「画面で何px」で決め、ズームで割って渡す
//              （拡大しても線が太らない）。
//   画面座標 … 部屋名・アイコン・ピン・現在地。回転しても文字は水平、
//              拡大しても同じ大きさ。重なるラベルは優先度の低いほうを出さない。
//
// 部屋の形は FloorGeometry が一度だけ作る。ここは毎フレーム描くだけ。
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../data/map_data.dart';
import '../../navigation/route_geometry.dart';
import '../place_category.dart';
import '../theme.dart';
import 'floor_geometry.dart';
import 'map_camera.dart';

/// 経路のうち、このフロアの部分がいまどういう状態か。
enum RouteLeg {
  /// 歩いているフロア。歩き終えた部分は色を落とす。
  active,

  /// これから行くフロア。
  upcoming,

  /// もう通り過ぎたフロア。
  done,
}

/// 経路上のチェックポイントの印。
@immutable
class MapCheckpoint {
  final Offset point;
  final IconData icon;
  final Color color;

  /// 次に通るもの。大きく出す。
  final bool isNext;
  const MapCheckpoint(this.point, this.icon, this.color, {this.isNext = false});
}

/// 階の移り目の印（「2Fへ」など）。
@immutable
class MapTransfer {
  final Offset point;
  final String text;
  final IconData icon;
  const MapTransfer(this.point, this.text, this.icon);
}

/// 1フレームに描くものの一式。画面（MapScreen）が組み立てる。
@immutable
class MapScene {
  final FloorMap floor;
  final RouteGeometry? route;
  final RouteLeg leg;
  final double traveledPx;
  final List<MapCheckpoint> checkpoints;
  final MapTransfer? transfer;

  /// 出発地の印。現在地の点を出さないとき（別の階を見ているなど）だけ。
  final Offset? startPoint;

  final Offset? goalPoint;
  final String? goalName;

  /// 選んでいる場所（ピンと、部屋の強調）。
  final Offset? pinPoint;
  final String? highlightName;

  /// 現在地の点を出すか。位置そのものは MapViewController が持つ。
  final bool showUser;

  /// 現在地の誤差の目安（JSON-px）。
  final double uncertaintyPx;

  /// 部屋名の文字の基本スタイル（フォントなど）。
  final TextStyle labelStyle;

  /// 地図の上に浮かんでいる UI の場所（画面座標）。部屋名はここに出さない。
  final List<Rect> obstacles;

  const MapScene({
    required this.floor,
    required this.labelStyle,
    this.route,
    this.leg = RouteLeg.upcoming,
    this.traveledPx = 0,
    this.checkpoints = const [],
    this.transfer,
    this.startPoint,
    this.goalPoint,
    this.goalName,
    this.pinPoint,
    this.highlightName,
    this.showUser = false,
    this.uncertaintyPx = 0,
    this.obstacles = const [],
  });
}

class MapPainter extends CustomPainter {
  final MapScene scene;
  final MapViewController view;

  MapPainter({required this.scene, required this.view})
      : super(repaint: Listenable.merge([view, PaintingBinding.instance.systemFonts]));

  // ─── 文字のキャッシュ ─────────────────────────────────────────
  // 部屋名は数百あり、毎フレーム組版し直すと重い。組版済みのものを使い回す。
  // Web では日本語フォントが後から届くので、届いたら捨てて組み直す。
  static final LinkedHashMap<String, _Label> _labels = LinkedHashMap();
  static int _fontsVersion = 0;
  static int _cachedFontsVersion = 0;
  static bool _watchingFonts = false;

  static void _checkFonts() {
    if (!_watchingFonts) {
      _watchingFonts = true;
      PaintingBinding.instance.systemFonts.addListener(() => _fontsVersion++);
    }
    if (_cachedFontsVersion != _fontsVersion) {
      for (final l in _labels.values) {
        l.dispose();
      }
      _labels.clear();
      _cachedFontsVersion = _fontsVersion;
    }
  }

  /// テストなどで文字のキャッシュを捨てる。
  static void clearCache() {
    for (final l in _labels.values) {
      l.dispose();
    }
    _labels.clear();
  }

  _Label _label(String text, TextStyle style,
      {double maxWidth = 120, TextAlign align = TextAlign.center}) {
    final key = '$text|${style.hashCode}|$maxWidth|${align.index}';
    final hit = _labels.remove(key);
    if (hit != null) return _labels[key] = hit;
    final label = _Label(text, style, maxWidth, align);
    _labels[key] = label;
    while (_labels.length > 700) {
      _labels.remove(_labels.keys.first)?.dispose();
    }
    return label;
  }

  // ─── 描画 ───────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    _checkFonts();
    final geo = FloorGeometry.of(scene.floor);
    final cam = view.camera;
    final focal = view.focal;
    final outdoorMap = scene.floor.section.outdoor;

    canvas.drawRect(Offset.zero & size,
        Paint()..color = outdoorMap ? AppColors.mapGround : AppColors.mapBackground);

    canvas.save();
    canvas.translate(focal.dx, focal.dy);
    canvas.rotate(-cam.bearing);
    canvas.scale(cam.zoom);
    canvas.translate(-cam.center.dx, -cam.center.dy);
    final px = 1 / cam.zoom; // 画面の1px を地図座標で
    final visible = view.visibleMapRect.inflate(40 * px);

    _paintFloor(canvas, geo, px, visible, outdoorMap);
    _paintHighlights(canvas, geo, px);
    _paintRoute(canvas, px);

    canvas.restore();

    _paintRouteChevrons(canvas, size);
    _paintLabels(canvas, size, geo);
    _paintMarkers(canvas);
    _paintUser(canvas);
  }

  void _paintFloor(
      Canvas canvas, FloorGeometry geo, double px, Rect visible, bool outdoorMap) {
    final fill = Paint()..isAntiAlias = true;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    // 屋外（中庭・構内）
    fill.color = AppColors.mapOutdoor;
    canvas.drawPath(geo.outdoor, fill);

    if (!outdoorMap) {
      // 建物の影。床を少し浮かせて見せる。
      canvas.save();
      canvas.translate(0, 2.5 * px);
      canvas.drawPath(
        geo.footprint,
        Paint()
          ..color = const Color(0x2A3C4043)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 5 * px),
      );
      canvas.restore();
      fill.color = AppColors.mapFloor;
      canvas.drawPath(geo.footprint, fill);
    }

    // 通路
    fill.color = outdoorMap ? const Color(0xFFFBFAF7) : AppColors.mapCorridor;
    canvas.drawPath(geo.corridors, fill);
    if (outdoorMap) {
      stroke
        ..color = const Color(0xFFD9D4CA)
        ..strokeWidth = 1 * px;
      canvas.drawPath(geo.corridors, stroke);
    }

    // 部屋・建物
    for (final room in geo.rooms) {
      if (!room.bounds.overlaps(visible)) continue;
      if (room.isConnector) {
        fill.color = AppColors.mapCorridor;
        canvas.drawPath(room.path, fill);
        continue;
      }
      final cat = room.category;
      if (cat.kind == PlaceKind.building) {
        // 建物は少しずらした影で浮かせる。ぼかしは数が多いと重いので使わない。
        canvas.save();
        canvas.translate(1.5 * px, 2.5 * px);
        canvas.drawPath(room.path, Paint()..color = const Color(0x263C4043));
        canvas.restore();
      }
      fill.color = cat.fill;
      canvas.drawPath(room.path, fill);
      final hatch = room.hatch;
      if (hatch != null && 1 / px > 0.18) {
        stroke
          ..color = cat.stroke
          ..strokeWidth = 1 * px;
        canvas.drawPath(hatch, stroke);
      }
      stroke
        ..color = cat.stroke
        ..strokeWidth = (cat.kind == PlaceKind.building ? 1.2 : 1) * px;
      canvas.drawPath(room.path, stroke);
    }

    // 壁と扉（扉は壁を床色で切り欠いて開口に見せる）
    stroke
      ..color = AppColors.mapWall
      ..strokeWidth = math.max(1.4 * px, 1.2)
      ..strokeCap = StrokeCap.square;
    canvas.drawPath(geo.walls, stroke);
    stroke
      ..color = AppColors.mapCorridor
      ..strokeWidth = math.max(2.6 * px, 2.4)
      ..strokeCap = StrokeCap.butt;
    canvas.drawPath(geo.doors, stroke);

    if (!outdoorMap) {
      stroke
        ..color = AppColors.mapBuildingEdge
        ..strokeWidth = 1.5 * px
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(geo.footprint, stroke);
    }
  }

  void _paintHighlights(Canvas canvas, FloorGeometry geo, double px) {
    void outline(String? name, Color color, Color tint) {
      if (name == null) return;
      final room = geo.roomByName[name];
      if (room == null) return;
      // 半透明の色を重ねると部屋の色と混ざって灰色に見えるので、塗り直す。
      canvas.drawPath(room.path, Paint()..color = tint);
      canvas.drawPath(
        room.path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 2.2 * px
          ..color = color,
      );
    }

    if (scene.goalName != scene.highlightName) {
      outline(scene.goalName, AppColors.destination, const Color(0xFFFCE3E0));
    }
    outline(scene.highlightName, const Color(0xFF4A8AF4), const Color(0xFFDDE9FD));
  }

  // ─── 経路 ───────────────────────────────────────────────────

  void _paintRoute(Canvas canvas, double px) {
    final route = scene.route;
    if (route == null || route.display.length < 2) return;

    Path pathOf(List<Offset> pts) {
      final p = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final q in pts.skip(1)) {
        p.lineTo(q.dx, q.dy);
      }
      return p;
    }

    Paint line(Color color, double width) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = width * px
      ..color = color;

    void remaining(List<Offset> pts) {
      if (pts.length < 2) return;
      final p = pathOf(pts);
      canvas.drawPath(p, line(AppColors.routeCasing, 9.5));
      canvas.drawPath(p, line(AppColors.route, 6.5));
    }

    void passed(List<Offset> pts) {
      if (pts.length < 2) return;
      final p = pathOf(pts);
      canvas.drawPath(p, line(const Color(0xFF8FA3C2), 8));
      canvas.drawPath(p, line(AppColors.routePassed, 5.5));
    }

    switch (scene.leg) {
      case RouteLeg.active:
        passed(route.polylineUntil(scene.traveledPx));
        remaining(route.polylineFrom(scene.traveledPx));
      case RouteLeg.upcoming:
        remaining(route.display);
      case RouteLeg.done:
        passed(route.display);
    }
  }

  /// 経路の上に進む向きの山形を等間隔に描く（画面座標）。
  void _paintRouteChevrons(Canvas canvas, Size size) {
    final route = scene.route;
    if (route == null || scene.leg == RouteLeg.done) return;
    final pts = scene.leg == RouteLeg.active
        ? route.polylineFrom(scene.traveledPx)
        : route.display;
    if (pts.length < 2) return;
    final screen = [for (final p in pts) view.toScreen(p)];
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white.withValues(alpha: 0.95);
    const spacing = 64.0;
    var carry = spacing / 2;
    final bounds = (Offset.zero & size).inflate(20);
    for (var i = 0; i < screen.length - 1; i++) {
      final a = screen[i], b = screen[i + 1];
      final seg = (b - a).distance;
      if (seg < 0.5) continue;
      final dir = (b - a) / seg;
      var d = carry;
      while (d < seg) {
        final c = a + dir * d;
        if (bounds.contains(c)) {
          final n = Offset(-dir.dy, dir.dx);
          final tip = c + dir * 2.6;
          final path = Path()
            ..moveTo((tip - dir * 4.2 + n * 3.4).dx, (tip - dir * 4.2 + n * 3.4).dy)
            ..lineTo(tip.dx, tip.dy)
            ..lineTo((tip - dir * 4.2 - n * 3.4).dx, (tip - dir * 4.2 - n * 3.4).dy);
          canvas.drawPath(path, paint);
        }
        d += spacing;
      }
      carry = d - seg;
    }
  }

  // ─── ラベル ─────────────────────────────────────────────────

  void _paintLabels(Canvas canvas, Size size, FloorGeometry geo) {
    final cam = view.camera;
    final zoom = cam.zoom;
    final c = math.cos(cam.bearing).abs(), s = math.sin(cam.bearing).abs();
    final viewport = (Offset.zero & size).inflate(30);
    final placed = <Rect>[...scene.obstacles];
    // 現在地の点・ピンの上には文字を重ねない。
    final dot = view.userDot;
    if (scene.showUser && dot != null) {
      placed.add(Rect.fromCircle(center: view.toScreen(dot), radius: 13));
    }
    for (final p in [scene.goalPoint, scene.pinPoint]) {
      if (p == null) continue;
      final s = view.toScreen(p);
      placed.add(Rect.fromLTRB(s.dx - 13, s.dy - 37, s.dx + 13, s.dy));
    }

    // 画面の端のUI（検索欄・シート）の下に隠れる文字は出さない。
    final pad = view.padding;
    final usable = Rect.fromLTRB(
        0, pad.top - 8, size.width, size.height - pad.bottom + 8);

    bool free(Rect r) {
      if (!usable.overlaps(r)) return false;
      for (final p in placed) {
        if (p.overlaps(r)) return false;
      }
      return true;
    }

    final base = scene.labelStyle;
    final roomStyle = base.copyWith(
        fontSize: 11.5,
        fontWeight: FontWeight.w500,
        color: AppColors.mapLabel,
        height: 1.15,
        letterSpacing: 0);

    // 優先度順に並べる: 強調中 > 目印（トイレ・階段など） > 広い部屋。
    final rooms = geo.rooms.where((r) => r.name.isNotEmpty).toList()
      ..sort((a, b) {
        int rank(RoomShape r) {
          if (r.name == scene.highlightName || r.name == scene.goalName) return 0;
          if (r.category.isLandmark) return 1;
          return 2;
        }

        final d = rank(a).compareTo(rank(b));
        return d != 0 ? d : b.cellCount.compareTo(a.cellCount);
      });

    for (final room in rooms) {
      final p = view.toScreen(room.anchor);
      if (!viewport.contains(p)) continue;
      final isFocus =
          room.name == scene.highlightName || room.name == scene.goalName;
      // 部屋が画面上でどれだけの大きさに見えているか（回転も考える）。
      final w = (room.bounds.width * c + room.bounds.height * s) * zoom;
      final h = (room.bounds.width * s + room.bounds.height * c) * zoom;

      if (room.isConnector) {
        if (zoom < 0.9) continue;
        final r = Rect.fromCircle(center: p, radius: 9);
        if (!free(r)) continue;
        _badge(canvas, p, Icons.swap_vert, const Color(0xFF7B4FC9), 8);
        placed.add(r.inflate(2));
        continue;
      }

      final cat = room.category;
      final text = displayPlaceName(room.name);

      if (isFocus) {
        // 強調中の部屋名はピンの下に太字で必ず出す。
        final color = room.name == scene.highlightName
            ? AppColors.primaryDark
            : AppColors.destinationDark;
        final label = _label(
            text,
            base.copyWith(
                fontSize: 13, fontWeight: FontWeight.w700, color: color, height: 1.15),
            maxWidth: 150);
        final at = p + Offset(-label.width / 2, 6);
        label.paint(canvas, at);
        placed.add((at & label.size).inflate(4));
        continue;
      }

      if (cat.isLandmark || cat.kind == PlaceKind.sports || cat.kind == PlaceKind.water ||
          cat.kind == PlaceKind.parking) {
        // 目印はアイコンだけでも出す。余裕があれば名前を右に添える。
        if (math.min(w, h) < 7) continue;
        const r = 9.0;
        final iconRect = Rect.fromCircle(center: p, radius: r + 1);
        if (!free(iconRect)) continue;
        final label = _label(
            text,
            roomStyle.copyWith(
                color: Color.lerp(cat.accent, Colors.black, 0.25),
                fontWeight: FontWeight.w600),
            maxWidth: 150,
            align: TextAlign.left);
        final textAt = Offset(p.dx + r + 3, p.dy - label.height / 2);
        final textRect = (textAt & label.size).inflate(2);
        final showText = zoom > 0.22 && free(textRect);
        _badge(canvas, p, cat.icon, cat.accent, r);
        placed.add(iconRect);
        if (showText) {
          label.paint(canvas, textAt);
          placed.add(textRect);
        }
        continue;
      }

      final label = _label(text, roomStyle, maxWidth: math.max(56, math.min(120, w)));
      // 部屋からはみ出すほど小さく見えているときは出さない。
      if (label.width > w * 1.15 + 6 || label.height > h + 4) continue;
      // 中央がふさがっていたら（現在地の点など）、上下にずらして置く。
      final shift = label.height / 2 + 17;
      for (final dy in [0.0, shift, -shift]) {
        if (dy != 0 && label.height + shift * 2 > h) break;
        final at = p - Offset(label.width / 2, label.height / 2 - dy);
        final rect = (at & label.size).inflate(3);
        if (!free(rect)) continue;
        label.paint(canvas, at);
        placed.add(rect);
        break;
      }
    }
  }

  void _badge(Canvas canvas, Offset p, IconData icon, Color color, double r) {
    canvas.drawCircle(p + const Offset(0, 0.8), r + 1.2,
        Paint()..color = const Color(0x33000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2));
    canvas.drawCircle(p, r + 1.2, Paint()..color = Colors.white);
    canvas.drawCircle(p, r, Paint()..color = color);
    final glyph = _label(
      String.fromCharCode(icon.codePoint),
      TextStyle(
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        fontSize: r * 1.3,
        color: Colors.white,
        height: 1,
      ),
      maxWidth: 100,
    );
    glyph.paintPlain(canvas, p - Offset(glyph.width / 2, glyph.height / 2));
  }

  // ─── 印 ─────────────────────────────────────────────────────

  void _paintMarkers(Canvas canvas) {
    for (final cp in scene.checkpoints) {
      final p = view.toScreen(cp.point);
      if (cp.isNext) {
        canvas.drawCircle(p, 15, Paint()..color = cp.color.withValues(alpha: 0.18));
        canvas.drawCircle(p + const Offset(0, 1), 11,
            Paint()..color = const Color(0x40000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
        canvas.drawCircle(p, 11, Paint()..color = Colors.white);
        canvas.drawCircle(p, 11, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = cp.color);
        final glyph = _label(
            String.fromCharCode(cp.icon.codePoint),
            TextStyle(
                fontFamily: cp.icon.fontFamily,
                package: cp.icon.fontPackage,
                fontSize: 13,
                color: cp.color,
                height: 1),
            maxWidth: 100);
        glyph.paintPlain(canvas, p - Offset(glyph.width / 2, glyph.height / 2));
      } else {
        canvas.drawCircle(p, 5.5, Paint()..color = Colors.white);
        canvas.drawCircle(p, 5.5, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = cp.color);
      }
    }

    final transfer = scene.transfer;
    if (transfer != null) _paintTransfer(canvas, transfer);

    final start = scene.startPoint;
    if (start != null) {
      final p = view.toScreen(start);
      canvas.drawCircle(p, 8, Paint()..color = Colors.white);
      canvas.drawCircle(p, 8, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = AppColors.textSecondary);
    }

    final goal = scene.goalPoint;
    if (goal != null) _paintPin(canvas, view.toScreen(goal), AppColors.destination);
    final pin = scene.pinPoint;
    if (pin != null && pin != goal) {
      _paintPin(canvas, view.toScreen(pin), AppColors.destination);
    }
  }

  void _paintTransfer(Canvas canvas, MapTransfer t) {
    final p = view.toScreen(t.point);
    final label = _label(
        t.text,
        scene.labelStyle.copyWith(
            fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white, height: 1.1),
        maxWidth: 160);
    const iconSize = 15.0;
    final w = 10 + iconSize + 4 + label.width + 12;
    const h = 28.0;
    final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(p.dx - w / 2, p.dy - h - 14, w, h), const Radius.circular(14));
    canvas.drawRRect(rect.shift(const Offset(0, 1.5)),
        Paint()..color = const Color(0x40000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    canvas.drawRRect(rect, Paint()..color = AppColors.routeCasing);
    // 吹き出しのしっぽ
    final tail = Path()
      ..moveTo(p.dx - 6, rect.bottom - 1)
      ..lineTo(p.dx, rect.bottom + 6)
      ..lineTo(p.dx + 6, rect.bottom - 1)
      ..close();
    canvas.drawPath(tail, Paint()..color = AppColors.routeCasing);
    final glyph = _label(
        String.fromCharCode(t.icon.codePoint),
        TextStyle(
            fontFamily: t.icon.fontFamily,
            package: t.icon.fontPackage,
            fontSize: iconSize,
            color: Colors.white,
            height: 1),
        maxWidth: 100);
    glyph.paintPlain(canvas, Offset(rect.left + 10, rect.center.dy - glyph.height / 2));
    label.paintPlain(
        canvas, Offset(rect.left + 10 + iconSize + 4, rect.center.dy - label.height / 2));
    canvas.drawCircle(p, 6, Paint()..color = Colors.white);
    canvas.drawCircle(p, 6, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = AppColors.routeCasing);
  }

  static final Path _pinShape = () {
    final head = Path()..addOval(Rect.fromCircle(center: const Offset(0, -23), radius: 12));
    final tail = Path()
      ..moveTo(-9.6, -15.8)
      ..quadraticBezierTo(-3, -8, 0, 0)
      ..quadraticBezierTo(3, -8, 9.6, -15.8)
      ..close();
    return Path.combine(PathOperation.union, head, tail);
  }();

  void _paintPin(Canvas canvas, Offset tip, Color color) {
    canvas.drawOval(Rect.fromCenter(center: tip, width: 12, height: 5),
        Paint()..color = const Color(0x40000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5));
    canvas.save();
    canvas.translate(tip.dx, tip.dy);
    canvas.drawPath(_pinShape.shift(const Offset(0, 1)),
        Paint()..color = const Color(0x33000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
    canvas.drawPath(_pinShape, Paint()..color = color);
    canvas.drawPath(
        _pinShape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Color.lerp(color, Colors.black, 0.25)!);
    canvas.drawCircle(const Offset(0, -23), 4.6, Paint()..color = Color.lerp(color, Colors.black, 0.45)!);
    canvas.restore();
  }

  // ─── 現在地 ─────────────────────────────────────────────────

  void _paintUser(Canvas canvas) {
    if (!scene.showUser) return;
    final pos = view.userDot;
    if (pos == null) return;
    final p = view.toScreen(pos);
    final cam = view.camera;

    // 誤差の円。歩くほど広がり、チェックポイントで縮む。
    final r = scene.uncertaintyPx * cam.zoom;
    if (r > 14) {
      final rr = math.min(r, 420.0);
      canvas.drawCircle(p, rr, Paint()..color = AppColors.userDot.withValues(alpha: 0.10));
      canvas.drawCircle(p, rr, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.userDot.withValues(alpha: 0.35));
    }

    // 向いている方向の扇。
    final heading = view.heading;
    if (heading != null) {
      final a = heading - cam.bearing;
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(a);
      const radius = 46.0;
      const spread = 0.62; // 片側の開き（ラジアン）
      final beam = Path()
        ..moveTo(0, 0)
        ..arcTo(Rect.fromCircle(center: Offset.zero, radius: radius),
            -math.pi / 2 - spread, spread * 2, false)
        ..close();
      canvas.drawPath(
        beam,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset.zero,
            radius,
            [
              AppColors.userDot.withValues(alpha: 0.42),
              AppColors.userDot.withValues(alpha: 0.0),
            ],
          ),
      );
      canvas.restore();
    }

    canvas.drawCircle(p + const Offset(0, 1), 10.5,
        Paint()..color = const Color(0x4D000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5));
    canvas.drawCircle(p, 10.5, Paint()..color = Colors.white);
    canvas.drawCircle(p, 7.5, Paint()..color = AppColors.userDot);
  }

  @override
  bool shouldRepaint(MapPainter old) => old.scene != scene || old.view != view;
}

/// 縁取りつきの文字（地図の上でも読めるように白く縁取る）。
class _Label {
  final TextPainter fill;
  final TextPainter halo;

  _Label(String text, TextStyle style, double maxWidth, TextAlign align)
      : fill = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: TextDirection.ltr,
          textAlign: align,
          maxLines: 2,
          ellipsis: '…',
        )..layout(maxWidth: maxWidth),
        halo = TextPainter(
          text: TextSpan(
            text: text,
            style: style.copyWith(
              color: null,
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 3.2
                ..strokeJoin = StrokeJoin.round
                ..color = Colors.white.withValues(alpha: 0.92),
            ),
          ),
          textDirection: TextDirection.ltr,
          textAlign: align,
          maxLines: 2,
          ellipsis: '…',
        )..layout(maxWidth: maxWidth);

  double get width => fill.width;
  double get height => fill.height;
  Size get size => fill.size;

  void paint(Canvas canvas, Offset at) {
    halo.paint(canvas, at);
    fill.paint(canvas, at);
  }

  void paintPlain(Canvas canvas, Offset at) => fill.paint(canvas, at);

  void dispose() {
    fill.dispose();
    halo.dispose();
  }
}
