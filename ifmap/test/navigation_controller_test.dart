// UIを起動せずに、ナビの筋道が通っているかを確かめる。
//
// initialize() は呼ばない（センサーと実アセットに触るため）。
// 代わりにマップを手で詰めたリポジトリを渡す。
import 'package:flutter_test/flutter_test.dart';
import 'package:ifmap/config.dart';
import 'package:ifmap/data/map_data.dart';
import 'package:ifmap/navigation/navigation_controller.dart';

Map<String, dynamic> _node(int cellX, int cellY,
        {List<String> edges = const [],
        String? name,
        Map<String, dynamic> extra = const {}}) =>
    {
      'x': cellX * AppConfig.pxPerCell,
      'y': cellY * AppConfig.pxPerCell,
      'edges': edges,
      'type': CellType.corridor,
      if (name != null) 'name': name,
      ...extra,
    };

FloorMap _floor(String label, int level, Map<String, dynamic> nodes) {
  final entry = <String, String>{};
  final destinations = <String>{};
  for (final e in nodes.entries) {
    final v = e.value as Map;
    final name = v['name'] as String?;
    if (name == null) continue;
    entry.putIfAbsent(name, () => e.key);
    if (v['isStairs'] != true && v['isConnector'] != true) {
      destinations.add(name);
    }
  }
  return FloorMap(
    section: MapSection(path: 'x', label: label, floorLevel: level),
    nodes: nodes,
    cells: const [],
    rooms: const [],
    roomCenters: const {},
    entryIdByName: entry,
    destinationNames: destinations,
  );
}

/// 使うマップは AppConfig.mapSections と同じラベルにしておく。
/// 階移動の探索順が mapSections の並びで決まるため。
const _f1 = 'NITTC_1F';
const _f2 = 'NITTC_2F';

MapRepository _repository() {
  final repo = MapRepository();
  repo.put(_floor(_f1, 1, {
    'a': _node(0, 0, edges: ['b'], name: '受付'),
    'b': _node(1, 0, edges: ['a', 's1']),
    's1': _node(2, 0,
        edges: ['b'], name: '中央階段', extra: {'isStairs': true}),
  }));
  repo.put(_floor(_f2, 2, {
    's2': _node(2, 0,
        edges: ['c'], name: '中央階段', extra: {'isStairs': true}),
    'c': _node(3, 0, edges: ['s2', 'd']),
    'd': _node(4, 0, edges: ['c'], name: '電算室'),
  }));
  return repo;
}

void main() {
  late NavigationController c;

  setUp(() => c = NavigationController(repository: _repository()));
  tearDown(() => c.dispose());

  group('出発地', () {
    test('名前から解決して表示フロアを合わせる', () async {
      await c.setStartByName('受付');
      expect(c.start, const PlaceRef('受付', _f1));
      expect(c.currentLabel, _f1);
      expect(c.trackerLabel, _f1);
      expect(c.showCompass, isTrue);
    });

    test('QRがURLでも start パラメータから読み取る', () async {
      await c.setStartByName(
          'https://aoi-nanndeyaneeen.github.io/IFMAP2/?start=%E5%8F%97%E4%BB%98');
      expect(c.start, const PlaceRef('受付', _f1));
    });

    test('見つからない名前は知らせて何も変えない', () async {
      final messages = <AppMessage>[];
      c.messages.listen(messages.add);

      await c.setStartByName('存在しない部屋');
      await Future<void>.delayed(Duration.zero);

      expect(c.start, isNull);
      expect(messages.single.kind, MessageKind.error);
    });
  });

  group('目的地', () {
    test('出発地がないと設定できない', () async {
      final messages = <AppMessage>[];
      c.messages.listen(messages.add);

      await c.setGoal(const PlaceRef('電算室', _f2));
      await Future<void>.delayed(Duration.zero);

      expect(c.goal, isNull);
      expect(messages.single.kind, MessageKind.error);
    });

    test('同一フロアなら経路は1フロア分', () async {
      await c.setStartByName('受付');
      await c.setGoal(const PlaceRef('中央階段', _f1));

      expect(c.floorPaths.keys, [_f1]);
      expect(c.currentPath, ['a', 'b', 's1']);
      expect(c.nextFloorLabel, isNull);
      expect(c.canAdvanceFloor, isFalse);
    });
  });

  group('階をまたぐ', () {
    setUp(() async {
      await c.setStartByName('受付');
      await c.setGoal(const PlaceRef('電算室', _f2));
    });

    test('全フロア分の経路を一度に持つ', () {
      expect(c.floorPaths.keys.toSet(), {_f1, _f2});
      expect(c.floorPaths[_f1]!.last, 's1');
      expect(c.floorPaths[_f2]!.first, 's2');
      expect(c.nextFloorLabel, _f2);
    });

    test('表示フロアを切り替えても再計算しない', () {
      final before = c.floorPaths;
      c.showFloor(_f2);

      expect(c.currentLabel, _f2);
      expect(c.trackerLabel, _f1, reason: '歩いているのはまだ1F');
      expect(c.currentPath, c.floorPaths[_f2]);
      expect(identical(c.floorPaths, before), isTrue);
    });

    test('表示だけ切り替えても現在地ドットは出さない', () {
      c.showFloor(_f2);
      expect(c.showUserDot, isFalse);

      c.showFloor(_f1);
      expect(c.showUserDot, isTrue);
    });

    test('次のフロアへ進むと出発地が降り口に移る', () async {
      await c.advanceToFloor(_f2);

      expect(c.trackerLabel, _f2);
      expect(c.currentLabel, _f2);
      expect(c.start, const PlaceRef('s2', _f2));
      expect(c.currentPath, ['s2', 'c', 'd']);
      expect(c.nextFloorLabel, isNull);
    });

    test('経路のないフロアへは進まない', () async {
      final messages = <AppMessage>[];
      c.messages.listen(messages.add);

      await c.advanceToFloor('HOME_1F');
      await Future<void>.delayed(Duration.zero);

      expect(c.trackerLabel, _f1);
      expect(messages.last.kind, MessageKind.error);
    });
  });

  group('同名の部屋', () {
    test('表示中のフロアのものを優先して解決する', () async {
      final repo = MapRepository();
      repo.put(_floor(_f1, 1, {'a': _node(0, 0, name: 'トイレ')}));
      repo.put(_floor(_f2, 2, {'b': _node(0, 0, name: 'トイレ')}));
      final ctrl = NavigationController(repository: repo);
      addTearDown(ctrl.dispose);

      ctrl.showFloor(_f2);
      await ctrl.setStartByName('トイレ');

      expect(ctrl.start, const PlaceRef('トイレ', _f2));
    });
  });

  group('リセット', () {
    test('出発地・目的地・経路をすべて捨てる', () async {
      await c.setStartByName('受付');
      await c.setGoal(const PlaceRef('電算室', _f2));

      c.reset();

      expect(c.start, isNull);
      expect(c.goal, isNull);
      expect(c.floorPaths, isEmpty);
      expect(c.nextFloorLabel, isNull);
      expect(c.followMode, isFalse);
      expect(c.position.value, isNull);
    });
  });
}
