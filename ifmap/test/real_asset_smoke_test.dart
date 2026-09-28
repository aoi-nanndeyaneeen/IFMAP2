// 実際にバンドルされているマップを1枚読み、
// エディタの出力形式とアプリの読み込みがずれていないかを確かめる。
//
// 単体テストがいくら通っても、エディタ側のJSONの形が変わると
// 実機で初めて壊れているとわかる。そこを塞ぐための1本。
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ifmap/config.dart';
import 'package:ifmap/data/map_data.dart';
import 'package:ifmap/routing/route_calculator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const section = MapSection(
      path: 'assets/home/home_1F.json', label: 'HOME_1F', floorLevel: 1);

  late FloorMap floor;

  setUpAll(() async {
    final content = await rootBundle.loadString(section.path);
    final parsed = parseFloorJson(content);
    floor = FloorMap(
      section: section,
      nodes: (parsed['nodes'] as Map).cast<String, dynamic>(),
      cells: parsed['cells'] as List<dynamic>,
      rooms: parsed['rooms'] as List<dynamic>,
      roomCenters: {
        for (final e in (parsed['roomCenters'] as Map).entries)
          e.key as String: Offset(
              (e.value as List)[0] as double, (e.value as List)[1] as double)
      },
      entryIdByName: (parsed['entryIdByName'] as Map).cast<String, String>(),
      destinationNames: (parsed['destinations'] as List).cast<String>().toSet(),
    );
  });

  test('ノードとセルと部屋がそろって読める', () {
    expect(floor.nodes, isNotEmpty);
    expect(floor.cells, isNotEmpty);
    expect(floor.roomCenters, isNotEmpty);
    expect(floor.destinationNames, isNotEmpty);
  });

  test('ノードIDの規則がエディタの出力と一致している', () {
    // node_{行}-{列} で、x = 列 * pxPerCell, y = 行 * pxPerCell。
    // ここがずれるとセルの type がノードへ写らず、
    // チェックポイントが静かに消える。
    for (final e in floor.nodes.entries) {
      final n = e.value as Map;
      final col = ((n['x'] as num) / AppConfig.pxPerCell).round();
      final row = ((n['y'] as num) / AppConfig.pxPerCell).round();
      expect(e.key, 'node_$row-$col');
    }
  });

  test('セルの type がノードへ写っている', () {
    final typed = floor.nodes.values
        .where((n) => n is Map && n['type'] != null)
        .length;
    expect(typed, greaterThan(0));
    // 歩けるマスにはすべて type があるはず。
    expect(typed, floor.nodes.length);
  });

  test('目的地どうしが経路でつながっている', () {
    final names = floor.destinationNames.toList()..sort();
    expect(names.length, greaterThanOrEqualTo(2));

    final from = floor.nodeIdOf(names.first)!;
    final to = floor.nodeIdOf(names.last)!;
    final path = RouteCalculator.dijkstra(from, to, floor.nodes);

    expect(path, isNotEmpty);
    expect(path.first, from);
    expect(path.last, to);
  });

  test('代表ノードは必ず実在するノードを指す', () {
    for (final id in floor.entryIdByName.values) {
      expect(floor.nodes.containsKey(id), isTrue);
    }
  });
}
