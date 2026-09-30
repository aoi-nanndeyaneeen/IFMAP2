// 曲がり角の近道の補正と、位置合わせのタップを一定距離ごとに挟む仕組み。
import 'package:flutter_test/flutter_test.dart';
import 'package:ifmap/config.dart';
import 'package:ifmap/data/map_data.dart';
import 'package:ifmap/sensors/step_tracker.dart';

const _s = AppConfig.pxPerCell;

/// マス座標の並びから経路とノードを作る（すべて通路）。
(List<String>, Map<String, dynamic>) _route(List<(int, int)> cells) {
  final ids = <String>[];
  final nodes = <String, dynamic>{};
  for (final (x, y) in cells) {
    final id = 'n$x-$y';
    ids.add(id);
    nodes[id] = {'x': x * _s, 'y': y * _s, 'type': CellType.corridor, 'edges': <String>[]};
  }
  return (ids, nodes);
}

/// 東へ [east] マス、そのあと南へ [south] マス。
(List<String>, Map<String, dynamic>) _lShape(int east, int south) => _route([
      for (var x = 0; x <= east; x++) (x, 0),
      for (var y = 1; y <= south; y++) (east, y),
    ]);

void main() {
  group('曲がり角の近道', () {
    test('直線では1歩は歩幅ぶんだけ進む', () {
      final t = StepTracker(cornerBoost: 2);
      addTearDown(t.dispose);
      final (ids, nodes) = _route([for (var x = 0; x <= 200; x++) (x, 0)]);
      t.setRoute(ids, nodes);
      t.advanceSteps(1);
      expect(t.traveledPx, closeTo(AppConfig.stepLengthPx, 1e-9));
    });

    test('角の近くでは歩数の進みが2倍になる', () {
      final t = StepTracker(cornerBoost: 2);
      addTearDown(t.dispose);
      // 角は 100マス = 1000px の地点
      final (ids, nodes) = _lShape(100, 100);
      t.setRoute(ids, nodes);
      expect(t.corners, hasLength(1));

      t.advanceSteps(60); // 840px。角（1000px）まで2.5m=50px より遠い
      final before = t.traveledPx;
      expect(before, closeTo(60 * AppConfig.stepLengthPx, 1e-6));

      t.advanceSteps(11); // 154px 進み、途中から角の手前50px以内に入る
      final gained = t.traveledPx - before;
      expect(gained, greaterThan(11 * AppConfig.stepLengthPx));
      expect(gained, lessThanOrEqualTo(11 * AppConfig.stepLengthPx * 2));
    });

    test('倍率を1にすれば従来どおり', () {
      final t = StepTracker();
      addTearDown(t.dispose);
      final (ids, nodes) = _lShape(100, 100);
      t.setRoute(ids, nodes);
      t.advanceSteps(71);
      expect(t.traveledPx, closeTo(71 * AppConfig.stepLengthPx, 1e-6));
    });
  });

  group('位置合わせのチェックポイント', () {
    StepTracker make() {
      final t = StepTracker(turnCheckpoints: true);
      addTearDown(t.dispose);
      return t;
    }

    test('曲がり角にチェックポイントができる', () {
      final t = make();
      final (ids, nodes) = _lShape(40, 40); // 400px = 20m ずつ。30m未満
      t.setRoute(ids, nodes);

      final turns = t.orderedGates.where((g) => g.turn != null).toList();
      expect(turns, hasLength(1));
      expect(turns.single.label, '右に曲がる');
      expect(t.orderedGates.where((g) => g.isCheck), isEmpty);
    });

    test('何もない長い直線には30mごとに確認を挟む', () {
      final t = make();
      // 100m = 2000px = 200マス
      final (ids, nodes) = _route([for (var x = 0; x <= 200; x++) (x, 0)]);
      t.setRoute(ids, nodes);

      final checks = t.orderedGates.where((g) => g.isCheck).toList();
      expect(checks, hasLength(3)); // 25m間隔で3つ → どの間隔も30m以下

      final xs = [0.0, ...t.orderedGates.map((g) => g.px!), t.totalRoutePx];
      for (var i = 1; i < xs.length; i++) {
        expect((xs[i] - xs[i - 1]) * AppConfig.metersPerPx, lessThanOrEqualTo(30.0001));
      }
    });

    test('近くの扉と曲がり角は1回のタップにまとめる', () {
      final t = make();
      final (ids, nodes) = _lShape(40, 40);
      // 角のすぐ手前に扉
      nodes['n39-0']['doorRight'] = true;
      t.setRoute(ids, nodes);

      expect(t.orderedGates.where((g) => g.isDoor), hasLength(1));
      expect(t.orderedGates.where((g) => g.turn != null), isEmpty);
    });

    test('タップするまでチェックポイントより先へは進まず、押すとそこへ合う', () {
      final t = make();
      final (ids, nodes) = _lShape(40, 40);
      t.setRoute(ids, nodes);
      final corner = t.nextGate!;

      t.advanceSteps(100);
      expect(t.traveledPx, closeTo(corner.px!, 1e-6));

      t.confirmGate(corner.key);
      expect(t.traveledPx, closeTo(corner.px!, 1e-6));
      expect(t.nextGate, isNull);
    });

    test('既定では増やさない', () {
      final t = StepTracker();
      addTearDown(t.dispose);
      final (ids, nodes) = _route([for (var x = 0; x <= 200; x++) (x, 0)]);
      t.setRoute(ids, nodes);
      expect(t.orderedGates, isEmpty);
    });
  });
}
