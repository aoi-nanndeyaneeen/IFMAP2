// lib/sensors/turn_matching.dart
//
// 曲がり角を目印にして、歩数で溜まった誤差を消すための部品。
//
// 方位で現在地を直接動かすことはしない。振り返っただけで点が飛んだり、
// 通路の中で1マス横にずれただけで反応したりして使いにくくなるため。
// 代わりに
//   1. 経路から「本当の曲がり角」だけを取り出す（extractCorners）
//   2. 方位の変化から「曲がった」ことを検出する（TurnDetector）
//   3. 推定位置の近くに、同じ向き・同じくらいの角度の曲がり角があるときだけ
//      「いまその角を曲がった」として位置を合わせる（StepTracker 側）
// という形にしている。方位の絶対値ではなく変化量だけを使うので、
// 屋内で鉄骨などにより方位が一定量ずれていても影響を受けにくい。
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

/// 角度を (-180, 180] に丸める。
double wrapDegrees(double d) {
  var x = d % 360;
  if (x > 180) x -= 360;
  if (x <= -180) x += 360;
  return x;
}

/// 経路上の曲がり角。
@immutable
class RouteCorner {
  /// 経路の始点からの距離(JSON-px)。
  final double distance;

  /// 曲がる角度(度)。時計回り（右折）が正。
  final double turn;

  const RouteCorner(this.distance, this.turn);

  @override
  String toString() =>
      'RouteCorner(${distance.toStringAsFixed(0)}px, ${turn.toStringAsFixed(0)}°)';
}

/// 経路の折れ線から、目印に使える曲がり角を取り出す。
///
/// [points] は経路のノード座標、[cumDist] はそれぞれの始点からの距離。
/// マス目の経路は斜めに進むとき階段状にジグザグし、通路の中で1マス
/// 横にずれることもあるので、まず線を単純化（Douglas-Peucker）してから
/// 角度を見る。
List<RouteCorner> extractCorners(
  List<Offset> points,
  List<double> cumDist, {
  double simplifyTolerancePx = 15,
  double minTurnDegrees = 45,
  double mergeWithinPx = 30,
}) {
  if (points.length < 3) return const [];

  final keep = List<bool>.filled(points.length, false);
  keep[0] = true;
  keep[points.length - 1] = true;
  _douglasPeucker(points, 0, points.length - 1, simplifyTolerancePx, keep);
  final idx = [for (var i = 0; i < points.length; i++) if (keep[i]) i];

  final raw = <RouteCorner>[];
  for (var k = 1; k < idx.length - 1; k++) {
    final a = points[idx[k - 1]], b = points[idx[k]], c = points[idx[k + 1]];
    final inAngle = math.atan2(b.dy - a.dy, b.dx - a.dx);
    final outAngle = math.atan2(c.dy - b.dy, c.dx - b.dx);
    // キャンバスは y が下向きなので、角度の増加は画面上の時計回り。
    // 北が上の地図なら、方位（磁北から時計回り）の変化と符号がそろう。
    final turn = wrapDegrees((outAngle - inAngle) * 180 / math.pi);
    raw.add(RouteCorner(cumDist[idx[k]], turn));
  }

  // 近くにある同じ向きの曲がりはひとつにまとめる（45°+45° の角など）。
  final merged = <RouteCorner>[];
  for (final c in raw) {
    if (merged.isNotEmpty) {
      final last = merged.last;
      if (c.distance - last.distance <= mergeWithinPx &&
          last.turn.sign == c.turn.sign) {
        merged[merged.length - 1] = RouteCorner(
            (last.distance + c.distance) / 2, wrapDegrees(last.turn + c.turn));
        continue;
      }
    }
    merged.add(c);
  }

  return [for (final c in merged) if (c.turn.abs() >= minTurnDegrees) c];
}

void _douglasPeucker(
    List<Offset> p, int first, int last, double tol, List<bool> keep) {
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
    _douglasPeucker(p, first, maxI, tol, keep);
    _douglasPeucker(p, maxI, last, tol, keep);
  }
}

/// 方位の変化から検出した「曲がった」という出来事。
@immutable
class TurnEvent {
  /// 新しい向きが安定したと判定した時刻（秒）。
  final double t;

  /// 曲がった角度（度）。時計回り（右折）が正。
  final double delta;

  const TurnEvent(this.t, this.delta);
}

/// 方位の変化から「曲がった」ことを検出する。
class TurnDetector {
  /// 新しい向きでこれだけ安定したら曲がったとみなす（秒）。
  /// ちらっと振り返っただけでは反応しないように。
  final double stableSeconds;

  /// 安定しているとみなす、窓の中での向きのばらつきの上限（度）。
  final double maxSpread;

  /// 安定しているとみなす回転の速さの上限（度/秒）。窓の前半と後半の
  /// 平均の差から求める。ゆっくり曲がっている最中を「曲がり終えた」と
  /// 誤って判定し、角度を小さく見積もるのを防ぐ。
  final double maxRate;

  /// これ以上向きが変わったら曲がったとみなす（度）。
  final double minTurn;

  /// これ未満の変化は歩きながらのふらつき・ゆるいカーブとして
  /// 基準の向きに吸収する（度）。これ以上 [minTurn] 未満の変化は
  /// 吸収せずに溜めるので、ゆっくり曲がっても取りこぼさない。
  final double driftAbsorb;

  TurnDetector({
    this.stableSeconds = 1.0,
    this.maxSpread = 20,
    this.maxRate = 10,
    this.minTurn = 45,
    this.driftAbsorb = 15,
  });

  final List<(double, double)> _window = [];
  double? _reference;

  /// 基準にしている向き（診断用）。
  double? get reference => _reference;

  /// 方位のサンプルを入れる。[t] は秒、[heading] は磁北から時計回りの度。
  /// 曲がったと判定した瞬間だけ [TurnEvent] を返す。
  TurnEvent? addHeading(double t, double heading) {
    _window.add((t, heading));
    while (_window.first.$1 < t - stableSeconds) {
      _window.removeAt(0);
    }
    // 窓がほぼ埋まるまでは判定しない
    if (_window.first.$1 > t - stableSeconds * 0.9) return null;

    final mean = _circularMean(_window);
    for (final (_, h) in _window) {
      // 向きを変えている最中、または手元でぶれている
      if (wrapDegrees(h - mean).abs() > maxSpread) return null;
    }
    final half = _window.length ~/ 2;
    if (half > 0) {
      final rate = wrapDegrees(_circularMean(_window.sublist(half)) -
                  _circularMean(_window.sublist(0, half)))
              .abs() /
          (stableSeconds / 2);
      if (rate > maxRate) return null; // まだ回っている
    }

    final ref = _reference;
    if (ref == null) {
      _reference = mean;
      return null;
    }
    final d = wrapDegrees(mean - ref);
    if (d.abs() >= minTurn) {
      _reference = mean;
      return TurnEvent(t, d);
    }
    if (d.abs() < driftAbsorb) _reference = mean;
    return null;
  }

  void reset() {
    _window.clear();
    _reference = null;
  }

  static double _circularMean(List<(double, double)> samples) {
    var sx = 0.0, sy = 0.0;
    for (final (_, h) in samples) {
      sx += math.cos(h * math.pi / 180);
      sy += math.sin(h * math.pi / 180);
    }
    return math.atan2(sy, sx) * 180 / math.pi;
  }
}
