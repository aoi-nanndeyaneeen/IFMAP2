// lib/navigation/route_geometry.dart
//
// 1フロア分の経路を「線」として扱うための計算。
//
// 経路はマスの中心を結んだ折れ線なので、斜めに進むところが階段状に
// ギザギザする。表示には Douglas-Peucker でならした線を使い、
// 現在地も同じ線の上に置く（生の経路の上に置くと、線から少し外れた
// ところに点が出る）。
//
// 距離はすべて生の経路に沿った JSON-px。歩数の推定（StepTracker）と
// 同じ物差しなので、進んだ距離をそのまま渡せば位置が出る。
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import '../config.dart';

class RouteGeometry {
  /// 生の経路（マスの中心）。
  final List<Offset> points;

  /// [points] の各点までの、経路に沿った距離。
  final List<double> cum;

  /// 表示用にならした線。部屋の中心からの引き出し線を含むことがある。
  final List<Offset> display;

  /// [display] の各点が、生の経路のどの距離に当たるか。
  final List<double> displayCum;

  RouteGeometry._(this.points, this.cum, this.display, this.displayCum);

  double get length => cum.isEmpty ? 0 : cum.last;

  Rect get bounds {
    var r = Rect.fromPoints(display.first, display.first);
    for (final p in display) {
      r = r.expandToInclude(Rect.fromPoints(p, p));
    }
    return r;
  }

  /// [path] はノードIDの並び。[head] / [tail] を渡すと、部屋の中心から
  /// 経路の端までの引き出し線を表示に足す（距離には数えない）。
  static RouteGeometry? build(
    List<String> path,
    Map<String, dynamic> nodes, {
    Offset? head,
    Offset? tail,
    double tolerancePx = 11,
  }) {
    final points = <Offset>[];
    for (final id in path) {
      final n = nodes[id];
      if (n is! Map) continue;
      points.add(Offset((n['x'] as num).toDouble() + AppConfig.cellCenter,
          (n['y'] as num).toDouble() + AppConfig.cellCenter));
    }
    if (points.isEmpty) return null;

    final cum = <double>[0];
    for (var i = 1; i < points.length; i++) {
      cum.add(cum.last + (points[i] - points[i - 1]).distance);
    }

    final keep = List<bool>.filled(points.length, false);
    keep[0] = keep[points.length - 1] = true;
    _dp(points, 0, points.length - 1, tolerancePx, keep);

    final display = <Offset>[];
    final displayCum = <double>[];
    if (head != null && (head - points.first).distance > 1) {
      display.add(head);
      displayCum.add(0);
    }
    for (var i = 0; i < points.length; i++) {
      if (!keep[i]) continue;
      display.add(points[i]);
      displayCum.add(cum[i]);
    }
    if (tail != null && (tail - points.last).distance > 1) {
      display.add(tail);
      displayCum.add(cum.last);
    }
    return RouteGeometry._(points, cum, display, displayCum);
  }

  /// 表示用の線の上で、経路に沿って [d] 進んだ点。
  Offset pointAt(double d) {
    final (i, t) = _segmentAt(d);
    if (i < 0) return display.first;
    if (i >= display.length - 1) return display.last;
    return Offset.lerp(display[i], display[i + 1], t)!;
  }

  /// [d] までに通った表示用の頂点と、[d] の点。歩き終えた部分を描くのに使う。
  List<Offset> polylineUntil(double d) {
    final (i, t) = _segmentAt(d);
    if (i < 0) return [display.first];
    if (i >= display.length - 1) return display;
    return [...display.sublist(0, i + 1), Offset.lerp(display[i], display[i + 1], t)!];
  }

  /// [d] から先の表示用の線。
  List<Offset> polylineFrom(double d) {
    final (i, t) = _segmentAt(d);
    if (i < 0) return display;
    if (i >= display.length - 1) return [display.last];
    return [Offset.lerp(display[i], display[i + 1], t)!, ...display.sublist(i + 1)];
  }

  /// [d] の地点で進む向き。地図の上を 0 とした時計回りのラジアン。
  /// 少し先（[lookahead]）の点を見るので、曲がり角の手前から
  /// なめらかに向きが変わる。
  double headingAt(double d, {double lookahead = 50}) {
    var a = pointAt(d);
    var b = pointAt(math.min(d + lookahead, length));
    if ((b - a).distance < 1) {
      // 終点。最後の区間の向きを使う。
      a = display.length >= 2 ? display[display.length - 2] : a;
      b = display.last;
    }
    return math.atan2(b.dx - a.dx, -(b.dy - a.dy));
  }

  /// 経路上の [d] の点を、生の経路で求める（チェックポイントの位置など）。
  Offset rawPointAt(double d) {
    if (d <= 0) return points.first;
    for (var i = 1; i < points.length; i++) {
      if (cum[i] >= d) {
        final seg = cum[i] - cum[i - 1];
        final t = seg == 0 ? 0.0 : (d - cum[i - 1]) / seg;
        return Offset.lerp(points[i - 1], points[i], t)!;
      }
    }
    return points.last;
  }

  /// [d] を含む表示用の区間の番号と、その中での割合。
  (int, double) _segmentAt(double d) {
    if (display.length < 2) return (-1, 0);
    for (var i = 0; i < display.length - 1; i++) {
      final a = displayCum[i], b = displayCum[i + 1];
      if (b <= a) continue; // 引き出し線（距離0）
      if (d <= b) {
        final t = ((d - a) / (b - a)).clamp(0.0, 1.0);
        return (i, t);
      }
    }
    return (display.length - 1, 1);
  }
}

void _dp(List<Offset> p, int first, int last, double tol, List<bool> keep) {
  if (last - first < 2) return;
  final a = p[first], b = p[last];
  final len = (b - a).distance;
  var maxD = -1.0;
  var maxI = -1;
  for (var i = first + 1; i < last; i++) {
    final d = len == 0
        ? (p[i] - a).distance
        : ((b.dx - a.dx) * (a.dy - p[i].dy) - (a.dx - p[i].dx) * (b.dy - a.dy))
                .abs() /
            len;
    if (d > maxD) {
      maxD = d;
      maxI = i;
    }
  }
  if (maxD > tol) {
    keep[maxI] = true;
    _dp(p, first, maxI, tol, keep);
    _dp(p, maxI, last, tol, keep);
  }
}
