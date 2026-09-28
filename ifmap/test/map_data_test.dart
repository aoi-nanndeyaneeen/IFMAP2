import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ifmap/config.dart';
import 'package:ifmap/data/map_data.dart';

/// ifmap_editor が書き出すのと同じ形のJSONを組み立てる。
/// ノードIDは node_{行}-{列}、セルは {x: 列, y: 行}。
String _sampleJson() => jsonEncode({
      'node_0-0': {
        'x': 0,
        'y': 0,
        'edges': ['node_0-1'],
      },
      'node_0-1': {
        'x': 10,
        'y': 0,
        'edges': ['node_0-0', 'node_0-2'],
        'name': '教室A',
      },
      'node_0-2': {
        'x': 20,
        'y': 0,
        'edges': ['node_0-1'],
        'name': '教室A',
      },
      'node_1-0': {
        'x': 0,
        'y': 10,
        'edges': <String>[],
        'name': '階段A',
        'isStairs': true,
      },
      '_editorData': {
        'bgImageBase64': null,
        'cells': [
          {'x': 0, 'y': 0, 'type': 1},
          {'x': 1, 'y': 0, 'type': 3, 'name': '教室A'},
          {'x': 2, 'y': 0, 'type': 3, 'name': '教室A'},
          {'x': 0, 'y': 1, 'type': 4, 'name': '階段A'},
        ],
        'rooms': [
          // 中心は node_0-2 (x=20,y=0 → 中心 25,5) のすぐ近くに置く。
          {'name': '教室A', 'centerX': 24.0, 'centerY': 5.0},
        ],
      },
    });

void main() {
  late FloorMap floor;

  setUp(() {
    final parsed = parseFloorJson(_sampleJson());
    final repo = MapRepository();
    repo.put(FloorMap(
      section: const MapSection(path: 'x', label: 'F1'),
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
    ));
    floor = repo.floor('F1')!;
  });

  group('parseFloorJson', () {
    test('_editorData はノード側に混ざらない', () {
      expect(floor.nodes.containsKey('_editorData'), isFalse);
      expect(floor.nodes, hasLength(4));
    });

    // これが効いていないと「部屋に入る/出る」のチェックポイントが
    // 一切生成されない。セル側にしか type がないのが原因。
    test('セルの type がノードへ写し込まれる', () {
      expect(floor.nodes['node_0-0']['type'], CellType.corridor);
      expect(floor.nodes['node_0-1']['type'], CellType.room);
      expect(floor.nodes['node_1-0']['type'], CellType.stairs);
    });

    test('部屋の中心にいちばん近いノードを代表にする', () {
      // 中心(24,5) に近いのは node_0-2 (中心 25,5)。
      expect(floor.entryIdByName['教室A'], 'node_0-2');
    });

    test('階段と接続点は目的地候補に入れない', () {
      expect(floor.destinationNames, {'教室A'});
    });
  });

  group('FloorMap', () {
    test('名前でもノードIDでも引ける', () {
      expect(floor.nodeIdOf('教室A'), 'node_0-2');
      expect(floor.nodeIdOf('node_0-0'), 'node_0-0');
      expect(floor.nodeIdOf('ない部屋'), isNull);
    });

    test('部屋は部屋の中心、ノードはマスの中心を返す', () {
      expect(floor.centerOf('教室A'), const Offset(24, 5));
      expect(floor.centerOf('node_0-0'), const Offset(5, 5));
    });
  });

  group('MapRepository', () {
    test('同名の部屋があるとき preferred のフロアを優先する', () {
      final repo = MapRepository();
      repo.put(_floorNamed('F1', 'トイレ'));
      repo.put(_floorNamed('F2', 'トイレ'));

      expect(repo.labelOf('トイレ'), 'F1'); // 指定なしなら先頭
      expect(repo.labelOf('トイレ', preferred: 'F2'), 'F2');
      expect(repo.labelsOf('トイレ'), ['F1', 'F2']);
    });

    test('存在しない名前は解決できない', () {
      final repo = MapRepository();
      repo.put(_floorNamed('F1', 'トイレ'));
      expect(repo.resolve('ない部屋'), isNull);
      expect(repo.resolve('トイレ'), const PlaceRef('トイレ', 'F1'));
    });

    test('フロアを指定して目的地を絞れる', () {
      final repo = MapRepository();
      repo.put(_floorNamed('F1', '教室1'));
      repo.put(_floorNamed('F2', '教室2'));

      expect(repo.destinations().map((p) => p.name), ['教室1', '教室2']);
      expect(repo.destinations(label: 'F2').map((p) => p.name), ['教室2']);
    });
  });
}

FloorMap _floorNamed(String label, String roomName) => FloorMap(
      section: MapSection(path: 'x', label: label),
      nodes: {
        'n': {'x': 0, 'y': 0, 'edges': <String>[], 'name': roomName}
      },
      cells: const [],
      rooms: const [],
      roomCenters: const {},
      entryIdByName: {roomName: 'n'},
      destinationNames: {roomName},
    );
