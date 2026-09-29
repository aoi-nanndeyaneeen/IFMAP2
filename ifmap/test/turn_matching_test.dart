// 曲がり角を目印にした位置の補正。
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ifmap/config.dart';
import 'package:ifmap/data/map_data.dart';
import 'package:ifmap/sensors/step_tracker.dart';
import 'package:ifmap/sensors/turn_matching.dart';

/// マス座標の並びから、点と累積距離を作る。
(List<Offset>, List<double>) _polyline(List<(int, int)> cells) {
  final pts = [
    for (final (x, y) in cells)
      Offset(x * AppConfig.pxPerCell, y * AppConfig.pxPerCell)
  ];
  final cum = <double>[0];
  for (var i = 1; i < pts.length; i++) {
    cum.add(cum.last + (pts[i] - pts[i - 1]).distance);
  }
  return (pts, cum);
}

List<(int, int)> _line((int, int) from, (int, int) to) {
  final out = <(int, int)>[];
  var (x, y) = from;
  final (tx, ty) = to;
  out.add((x, y));
  while (x != tx || y != ty) {
    x += (tx - x).sign;
    y += (ty - y).sign;
    out.add((x, y));
  }
  return out;
}

void main() {
  group('extractCorners', () {
    test('東へ進んで南へ曲がる経路は右90°の角が1つ', () {
      final cells = [..._line((0, 0), (20, 0)), ..._line((20, 1), (20, 20))];
      final (pts, cum) = _polyline(cells);
      final corners = extractCorners(pts, cum);
      expect(corners, hasLength(1));
      expect(corners.single.turn, closeTo(90, 1));
      expect(corners.single.distance, closeTo(200, 1));
    });

    test('東へ進んで北へ曲がるのは左（負）', () {
      final cells = [..._line((0, 20), (20, 20)), ..._line((20, 19), (20, 0))];
      final (pts, cum) = _polyline(cells);
      expect(extractCorners(pts, cum).single.turn, closeTo(-90, 1));
    });

    test('通路の中で1マス横にずれただけなら角ではない', () {
      final cells = [..._line((0, 0), (10, 0)), (10, 1), ..._line((11, 1), (25, 1))];
      final (pts, cum) = _polyline(cells);
      expect(extractCorners(pts, cum), isEmpty);
    });

    test('マス目の斜め移動（階段状のジグザグ）は角にしない', () {
      final cells = <(int, int)>[(0, 0)];
      for (var i = 0; i < 15; i++) {
        final (x, y) = cells.last;
        cells.add((x + 1, y));
        cells.add((x + 1, y + 1));
      }
      final (pts, cum) = _polyline(cells);
      expect(extractCorners(pts, cum), isEmpty);
    });

    test('近くの45°の曲がり2つは90°の角にまとめる', () {
      // 東 → 斜め2マス → 南
      final cells = [
        ..._line((0, 0), (20, 0)),
        (21, 1), (22, 2),
        ..._line((22, 3), (22, 20)),
      ];
      final (pts, cum) = _polyline(cells);
      final corners = extractCorners(pts, cum);
      expect(corners, hasLength(1));
      expect(corners.single.turn, closeTo(90, 1));
    });
  });

  group('TurnDetector', () {
    /// [heading] を時刻の関数として20Hzで流し、出てきた曲がりを返す。
    List<TurnEvent> feed(double Function(double t) heading, double seconds) {
      final d = TurnDetector();
      final out = <TurnEvent>[];
      for (var t = 0.0; t < seconds; t += 0.05) {
        final e = d.addHeading(t, heading(t));
        if (e != null) out.add(e);
      }
      return out;
    }

    test('はっきり右へ90°曲がると1回だけ検出する', () {
      final events = feed((t) => t < 3 ? 90 : (t < 3.5 ? 90 + (t - 3) * 180 : 180), 6);
      expect(events, hasLength(1));
      expect(events.single.delta, closeTo(90, 5));
    });

    test('4秒かけてゆっくり曲がっても、途中ではなく曲がり終えてから90°で出す', () {
      final events = feed((t) => t < 2 ? 0 : (t < 6 ? (t - 2) * 22.5 : 90), 9);
      expect(events, hasLength(1));
      expect(events.single.delta, closeTo(90, 8));
    });

    test('ちらっと振り返って戻っただけ（0.5秒）では出さない', () {
      final events = feed((t) => (t > 3 && t < 3.5) ? 180 : 0, 6);
      expect(events, isEmpty);
    });

    test('歩きながらのふらつき（±10°）では出さない', () {
      final rnd = math.Random(1);
      final events = feed((t) => 10 * (rnd.nextDouble() * 2 - 1), 20);
      expect(events, isEmpty);
    });

    test('北をまたいでも角度を正しく扱う（350°→80°は右90°）', () {
      final events = feed((t) => t < 3 ? 350 : ((t < 3.5 ? 350 + (t - 3) * 180 : 440) % 360), 6);
      expect(events.single.delta, closeTo(90, 5));
    });
  });

  group('StepTracker の曲がり角補正', () {
    // 東へ20マス(200px) → 南へ20マス。すべて廊下なのでチェックポイントはない。
    late double now;
    late StepTracker tracker;
    final cells = [..._line((0, 0), (20, 0)), ..._line((20, 1), (20, 20))];
    final path = [for (var i = 0; i < cells.length; i++) 'n$i'];
    final nodes = <String, dynamic>{
      for (var i = 0; i < cells.length; i++)
        'n$i': {
          'x': cells[i].$1 * AppConfig.pxPerCell,
          'y': cells[i].$2 * AppConfig.pxPerCell,
          'edges': <String>[],
          'type': CellType.corridor,
        },
    };

    setUp(() {
      now = 0;
      tracker = StepTracker(clock: () => now)..setRoute(path, nodes);
    });
    tearDown(() => tracker.dispose());

    /// [seconds] 秒ぶん、[heading] の向きで20Hzの方位を流す。
    /// [stepEvery] 秒ごとに1歩進める（null なら立ち止まっている）。
    void run(double Function(double t) heading, double seconds,
        {double? stepEvery}) {
      final end = now + seconds;
      var nextStep = stepEvery == null ? double.infinity : now + stepEvery;
      while (now < end) {
        now += 0.05;
        tracker.onHeading(heading(now));
        if (now >= nextStep) {
          tracker.advanceSteps(1);
          nextStep += stepEvery!;
        }
      }
    }

    test('経路の角を曲がったら、推定の遅れを角の位置まで取り戻す', () {
      expect(tracker.corners.single.distance, closeTo(200, 1));
      // 実際は200px地点の角にいるのに、歩数の推定は154pxで遅れている
      tracker.advanceSteps(11); // 154px
      run((_) => 90, 3); // 東を向いて立ち止まる（向きの基準を作る）
      // 角で南へ曲がり、歩き続ける
      final before = tracker.traveledPx;
      run((t) => 180, 2.5, stepEvery: 0.5);
      final stepsAfter = ((tracker.traveledPx - before) / AppConfig.stepLengthPx).round();
      // 曲がった時点で 200px に合わせられ、その後の歩数ぶん先にいる
      expect(tracker.traveledPx, greaterThan(200));
      expect(tracker.traveledPx, lessThanOrEqualTo(200 + 5 * AppConfig.stepLengthPx));
      expect(stepsAfter, greaterThan(5)); // 補正ぶん多く進んでいる
    });

    test('立ち止まって見回しただけでは補正しない', () {
      tracker.advanceSteps(11); // 154px
      run((_) => 90, 3);
      run((_) => 180, 5); // 南を向いたが歩かない
      expect(tracker.traveledPx, closeTo(154, 1e-6));
    });

    test('近くに一致する角がなければ補正しない', () {
      tracker.advanceSteps(2); // 28px。角(200px)から5m以上離れている
      run((_) => 90, 3);
      run((_) => 180, 2.5, stepEvery: 0.5);
      expect(tracker.traveledPx, closeTo(28 + 5 * AppConfig.stepLengthPx, 1e-6));
    });

    test('向きが逆（左に曲がった）なら右の角とは一致させない', () {
      tracker.advanceSteps(11);
      run((_) => 90, 3);
      run((_) => 0, 2.5, stepEvery: 0.5); // 北へ＝左90°
      expect(tracker.traveledPx, closeTo(154 + 5 * AppConfig.stepLengthPx, 1e-6));
    });
  });
}
