// 「どの建物にどの部屋があるか」の索引と、それを使った検索画面。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ifmap/config.dart';
import 'package:ifmap/data/campus_index.dart';
import 'package:ifmap/data/map_data.dart';
import 'package:ifmap/navigation/navigation_controller.dart';
import 'package:ifmap/ui/search_screen.dart';
import 'package:ifmap/ui/sensor_debug_sheet.dart';

Map<String, dynamic> _node(int x, String? name) => {
      'x': x * AppConfig.pxPerCell,
      'y': 0,
      'edges': <String>[],
      'type': CellType.room,
      if (name != null) 'name': name,
    };

FloorMap _floor(String label, int level, List<String> names) {
  final nodes = <String, dynamic>{
    for (var i = 0; i < names.length; i++) 'n$label$i': _node(i, names[i]),
  };
  return FloorMap(
    section: MapSection(path: 'x', label: label, floorLevel: level),
    nodes: nodes,
    cells: const [],
    rooms: const [],
    roomCenters: const {},
    entryIdByName: {for (final e in nodes.entries) e.value['name'] as String: e.key},
    destinationNames: names.toSet(),
  );
}

MapRepository _repo() {
  final repo = MapRepository();
  repo.put(_floor('EISHI_1F', 1, ['栄志寮_1F_食堂', '栄志寮_1F_玄関']));
  repo.put(_floor('EISHI_2F', 2, ['栄志寮_2F_談話室']));
  repo.put(_floor('KISHI_1F', 1, ['輝志寮_1F_食堂']));
  repo.put(_floor('NITTC_ground_1F', 1, ['図書館']));
  return repo;
}

const _index = '''
{
  "campus": "テスト", "note": "",
  "areas": [
    {"name": "学寮", "buildings": [
      {"name": "栄志寮", "floors": [
        {"floor": "1F", "label": "EISHI_1F", "rooms": [
          {"name": "食堂", "id": "栄志寮_1F_食堂"}, {"name": "玄関", "id": "栄志寮_1F_玄関"}]},
        {"floor": "2F", "label": "EISHI_2F", "rooms": [
          {"name": "談話室", "id": "栄志寮_2F_談話室"}]}]},
      {"name": "輝志寮", "floors": [
        {"floor": "1F", "label": "KISHI_1F", "rooms": [
          {"name": "食堂", "id": "輝志寮_1F_食堂"}, {"name": "消えた部屋", "id": "存在しない"}]}]}
    ]},
    {"name": "校舎", "buildings": [
      {"name": "図書館"}, {"name": "地図にない棟"}
    ]}
  ],
  "unassigned": {"name": "本棟（棟の特定できない部屋）", "floors": []}
}
''';

void main() {
  group('索引の読み込み', () {
    final index = CampusIndex.parse(_index, _repo());

    test('建物ごとに、階ごとの部屋を持つ', () {
      final b = index.visibleAreas.first.buildings.first;
      expect(b.name, '栄志寮');
      expect(b.roomsByFloor.keys, ['1F', '2F']);
      expect(b.roomCount, 3);
    });

    test('マップにない部屋は落とす', () {
      final kishi = index.visibleAreas.first.buildings.last;
      expect(kishi.rooms.map((r) => r.name), ['食堂']);
    });

    test('階のない建物は、同名の場所があればそれ自体を目的地にできる', () {
      final lib = index.visibleAreas[1].buildings.single;
      expect(lib.name, '図書館');
      expect(lib.self, const PlaceRef('図書館', 'NITTC_ground_1F'));
    });

    test('地図に載っていない建物は出さない', () {
      final names = index.visibleAreas.expand((a) => a.buildings).map((b) => b.name);
      expect(names, isNot(contains('地図にない棟')));
    });

    test('部屋から建物と短い名前を引ける', () {
      const p = PlaceRef('輝志寮_1F_食堂', 'KISHI_1F');
      expect(index.buildingOf(p)!.name, '輝志寮');
      expect(index.roomNameOf(p), '食堂');
    });

    test('索引にないマップは「その他のマップ」に建物ごとまとめる', () {
      final repo = _repo()..put(_floor('HOME_1F', 1, ['リビング']));
      final idx = CampusIndex.parse(_index, repo);
      final other = idx.visibleAreas.last;
      expect(other.name, 'その他のマップ');
      expect(other.buildings.single.name, '自宅');
    });
  });

  test('実データ: 索引の部屋がすべてマップ上にあり、建物ごとに探せる', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final repo = MapRepository();
    await repo.loadAll();
    final index = await CampusIndex.load(repo);

    final buildings = index.visibleAreas.expand((a) => a.buildings).toList();
    expect(buildings.length, greaterThan(15));
    for (final b in buildings) {
      expect(b.isEmpty, isFalse, reason: b.name);
      for (final r in b.rooms) {
        expect(repo.floor(r.place.label)?.nodeIdOf(r.place.name), isNotNull,
            reason: '${b.name} ${r.name}');
      }
    }
    final daishi = buildings.firstWhere((b) => b.name == '大志寮');
    expect(daishi.roomsByFloor.keys, containsAll(['1F', '2F', '3F', '4F']));

    // 建物に属さない目的地がどれくらい残っているか（屋外の施設などは除く）
    final orphans = [
      for (final p in repo.destinations())
        if (index.buildingOf(p) == null) '${p.label}:${p.name}'
    ];
    expect(orphans.length, lessThan(40), reason: orphans.take(20).join(', '));
  }, timeout: const Timeout(Duration(minutes: 3)));

  group('検索画面', () {
    late NavigationController c;

    setUp(() {
      final repo = _repo();
      c = NavigationController(repository: repo);
      c.campus = CampusIndex.parse(_index, repo);
    });
    tearDown(() => c.dispose());

    Future<void> open(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(home: PlaceSearchScreen(controller: c)));
      await tester.pump();
    }

    testWidgets('最初は建物の一覧が出る', (tester) async {
      await open(tester);
      expect(find.byKey(const ValueKey('building-list')), findsOneWidget);
      expect(find.text('栄志寮'), findsOneWidget);
      expect(find.text('輝志寮'), findsOneWidget);
      expect(find.text('学寮'), findsOneWidget);
    });

    testWidgets('建物を選ぶと、その建物の部屋だけが階ごとに出る', (tester) async {
      await open(tester);
      await tester.tap(find.text('栄志寮'));
      await tester.pump();

      expect(find.byKey(const ValueKey('building-chip')), findsOneWidget);
      expect(find.text('食堂'), findsOneWidget); // 輝志寮の食堂は出ない
      expect(find.text('談話室'), findsOneWidget);
      expect(find.text('2F'), findsWidgets);
    });

    testWidgets('戻るとまず建物の一覧へ戻る', (tester) async {
      await open(tester);
      await tester.tap(find.text('栄志寮'));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pump();

      expect(find.byKey(const ValueKey('building-list')), findsOneWidget);
    });

    testWidgets('建物名でも探せて、同じ名前の部屋は建物つきで区別できる', (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(const ValueKey('search-field')), '食堂');
      await tester.pump();
      expect(find.textContaining('栄志寮'), findsOneWidget);
      expect(find.textContaining('輝志寮'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('search-field')), '栄志寮');
      await tester.pump();
      expect(find.text('食堂'), findsOneWidget);
      expect(find.text('談話室'), findsOneWidget);
    });

    testWidgets('階のない建物を選ぶと、その場所を返す', (tester) async {
      PlaceRef? picked;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              picked = await Navigator.push<PlaceRef>(context,
                  MaterialPageRoute(builder: (_) => PlaceSearchScreen(controller: c)));
            },
            child: const Text('開く'),
          ),
        ),
      ));
      await tester.tap(find.text('開く'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('図書館'));
      await tester.pumpAndSettle();

      expect(picked, const PlaceRef('図書館', 'NITTC_ground_1F'));
    });
  });

  testWidgets('センサー診断は閉じるボタンで戻れる', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final c = NavigationController(repository: _repo());
    addTearDown(c.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showSensorDebugSheet(context, c),
          child: const Text('診断'),
        ),
      ),
    ));
    await tester.tap(find.text('診断'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('close-debug')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('close-debug')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('close-debug')), findsNothing);
  });
}
