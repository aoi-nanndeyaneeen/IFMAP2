import 'package:flutter_test/flutter_test.dart';
import 'package:ifmap/config.dart';
import 'package:ifmap/data/map_data.dart';
import 'package:ifmap/sensors/step_tracker.dart';

Map<String, dynamic> _node(int cellX, int cellY, int type,
        {String? name, Map<String, dynamic> extra = const {}}) =>
    {
      'x': cellX * AppConfig.pxPerCell,
      'y': cellY * AppConfig.pxPerCell,
      'edges': <String>[],
      'type': type,
      if (name != null) 'name': name,
      ...extra,
    };

void main() {
  late StepTracker tracker;

  setUp(() => tracker = StepTracker());
  tearDown(() => tracker.dispose());

  group('経路上の距離', () {
    test('ノード間の距離を積み上げる', () {
      tracker.setRoute(['a', 'b', 'c'], {
        'a': _node(0, 0, CellType.corridor),
        'b': _node(1, 0, CellType.corridor),
        'c': _node(3, 0, CellType.corridor),
      });
      // 1マス10px + 2マス20px = 30px
      expect(tracker.totalRoutePx, 30);
      expect(tracker.traveledPx, 0);
      expect(tracker.hasRoute, isTrue);
    });

    test('経路を捨てると距離もチェックポイントも消える', () {
      tracker.setRoute(['a', 'b'], {
        'a': _node(0, 0, CellType.corridor),
        'b': _node(1, 0, CellType.corridor),
      });
      tracker.clearRoute();
      expect(tracker.hasRoute, isFalse);
      expect(tracker.totalRoutePx, 0);
      expect(tracker.nextGate, isNull);
    });
  });

  group('チェックポイントの生成', () {
    // これは以前まったく動いていなかった。ノードに type がなく、
    // 部屋(type 3)の判定が常に false になっていたため。
    test('部屋から廊下へ出るところで「から出る」が出る', () {
      tracker.setRoute(['r1', 'r2', 'h1'], {
        'r1': _node(0, 0, CellType.room, name: '教室A'),
        'r2': _node(1, 0, CellType.room, name: '教室A'),
        'h1': _node(2, 0, CellType.corridor),
      });
      final gate = tracker.nextGate;
      expect(gate, isNotNull);
      expect(gate!.isEnter, isFalse);
      expect(gate.label, '「教室A」から出る');
    });

    test('廊下から部屋へ入るところで「に入る」が出る', () {
      tracker.setRoute(['h1', 'r1'], {
        'h1': _node(0, 0, CellType.corridor),
        'r1': _node(1, 0, CellType.room, name: '教室A'),
      });
      expect(tracker.nextGate!.label, '「教室A」に入る');
    });

    test('部屋を出て別の部屋に入ると2件そろう', () {
      tracker.setRoute(['a', 'h', 'b'], {
        'a': _node(0, 0, CellType.room, name: '教室A'),
        'h': _node(1, 0, CellType.corridor),
        'b': _node(2, 0, CellType.room, name: '教室B'),
      });
      expect(tracker.orderedGates.map((g) => g.label),
          ['「教室A」から出る', '「教室B」に入る']);
    });

    test('屋外へ出る・建物に入るを検出する', () {
      tracker.setRoute(['in', 'out', 'in2'], {
        'in': _node(0, 0, CellType.corridor),
        'out': _node(1, 0, CellType.outdoor),
        'in2': _node(2, 0, CellType.corridor),
      });
      expect(tracker.orderedGates.map((g) => g.label), ['外に出る', '建物に入る']);
    });

    test('屋外から接続点に入るときは「接続点に到達」', () {
      tracker.setRoute(['out', 'c'], {
        'out': _node(0, 0, CellType.outdoor),
        'c': _node(1, 0, CellType.connector, extra: {'isConnector': true}),
      });
      expect(tracker.orderedGates.map((g) => g.label), ['接続点に到達']);
    });

    test('廊下どうしをまたぐ扉を検出する', () {
      tracker.setRoute(['a', 'b'], {
        'a': _node(0, 0, CellType.corridor, extra: {'doorRight': true}),
        'b': _node(1, 0, CellType.corridor),
      });
      expect(tracker.orderedGates.map((g) => g.label), ['扉を通る']);
    });

    test('部屋の出入口の扉は二重に出さない', () {
      tracker.setRoute(['r', 'h'], {
        'r': _node(0, 0, CellType.room,
            name: '教室A', extra: {'doorRight': true}),
        'h': _node(1, 0, CellType.corridor),
      });
      expect(tracker.orderedGates, hasLength(1));
      expect(tracker.orderedGates.single.label, '「教室A」から出る');
    });

    test('type のないノードは廊下として扱う（古いJSONでも落ちない）', () {
      tracker.setRoute(['a', 'b'], {
        'a': {'x': 0, 'y': 0, 'edges': <String>[]},
        'b': {'x': 10, 'y': 0, 'edges': <String>[]},
      });
      expect(tracker.orderedGates, isEmpty);
      expect(tracker.totalRoutePx, 10);
    });
  });

  group('チェックポイントの確認', () {
    setUp(() {
      tracker.setRoute(['a', 'h', 'b'], {
        'a': _node(0, 0, CellType.room, name: '教室A'),
        'h': _node(1, 0, CellType.corridor),
        'b': _node(2, 0, CellType.room, name: '教室B'),
      });
    });

    test('確認するとそこまで進んだことになり、次へ進む', () {
      final first = tracker.nextGate!;
      tracker.confirmGate(first.key);
      expect(tracker.traveledPx, greaterThan(0));
      expect(tracker.nextGate!.label, '「教室B」に入る');
    });

    test('すでに通過したものをもう一度押しても巻き戻らない', () {
      final first = tracker.nextGate!;
      tracker.confirmGate(first.key);
      final afterFirst = tracker.traveledPx;
      tracker.confirmGate(first.key);
      expect(tracker.traveledPx, afterFirst);
    });

    test('最後のチェックポイントが経路の終端近くなら到着扱いになる', () {
      // 経路は20px、最後のゲートは15px地点。許容5pxなので到着とみなす。
      while (tracker.nextGate != null) {
        tracker.confirmGate(tracker.nextGate!.key);
      }
      expect(tracker.nextGate, isNull);
      expect(tracker.isAtRouteEnd, isTrue);
    });

    test('最後のチェックポイントから先がまだ残っていれば到着しない', () {
      tracker.setRoute(['a', 'h1', 'h2', 'h3', 'h4'], {
        'a': _node(0, 0, CellType.room, name: '教室A'),
        'h1': _node(1, 0, CellType.corridor),
        'h2': _node(2, 0, CellType.corridor),
        'h3': _node(3, 0, CellType.corridor),
        'h4': _node(4, 0, CellType.corridor),
      });
      while (tracker.nextGate != null) {
        tracker.confirmGate(tracker.nextGate!.key);
      }
      expect(tracker.isAtRouteEnd, isFalse);
    });
  });

  group('現在地の送出', () {
    // フロアを切り替えた直後に前のフロアの座標が残ると、
    // 現在地ドットが違う階に出たままになる。
    test('経路を差し替えたら即座に新しい先頭座標を流す', () async {
      final seen = <Offset?>[];
      final sub = tracker.positionStream.listen(seen.add);

      tracker.setRoute(['a', 'b'], {
        'a': _node(5, 5, CellType.corridor),
        'b': _node(6, 5, CellType.corridor),
      });
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(seen, isNotEmpty);
      expect(seen.last, const Offset(50, 50));
    });
  });
}
