// マス目のマップを図形（輪郭・壁・ラベル位置）に組み直す処理。

import 'package:flutter_test/flutter_test.dart';
import 'package:ifmap/config.dart';
import 'package:ifmap/data/map_data.dart';
import 'package:ifmap/ui/map/floor_geometry.dart';
import 'package:ifmap/ui/place_category.dart';

Set<int> _cells(List<(int, int)> xy) => {for (final (x, y) in xy) (y << 16) | x};

void main() {
  group('輪郭追跡', () {
    test('1マスは四角ひとつ', () {
      final loops = traceContours(_cells([(3, 4)]));
      expect(loops, hasLength(1));
      expect(loops.single.toSet(),
          {const Offset(3, 4), const Offset(4, 4), const Offset(4, 5), const Offset(3, 5)});
    });

    test('一直線に並ぶ頂点は省く', () {
      final loops = traceContours(_cells([
        for (var x = 0; x < 5; x++)
          for (var y = 0; y < 3; y++) (x, y),
      ]));
      expect(loops.single, hasLength(4));
    });

    test('L字は6頂点', () {
      final loops = traceContours(_cells([(0, 0), (0, 1), (1, 1)]));
      expect(loops.single, hasLength(6));
    });

    test('穴のある形は外周と穴の2つの輪', () {
      final loops = traceContours(_cells([
        for (var x = 0; x < 3; x++)
          for (var y = 0; y < 3; y++)
            if (x != 1 || y != 1) (x, y),
      ]));
      expect(loops, hasLength(2));
    });

    test('角だけで接するマスは別の輪にする', () {
      final loops = traceContours(_cells([(0, 0), (1, 1)]));
      expect(loops, hasLength(2));
      expect(loops.every((l) => l.length == 4), isTrue);
    });
  });

  test('1マスずつの段々は斜めの線にならす', () {
    // 右下がりの階段状の形
    final cells = _cells([
      for (var i = 0; i < 8; i++)
        for (var x = 0; x <= i; x++) (x, i),
    ]);
    final loop = traceContours(cells).single;
    final simple = simplifyLoop(loop, 0.75);
    expect(loop.length, greaterThan(10));
    expect(simple.length, lessThanOrEqualTo(4));
  });

  group('フロアの組み立て', () {
    const s = AppConfig.pxPerCell;
    Map<String, dynamic> cell(int x, int y, int type, [String? name]) =>
        {'x': x, 'y': y, 'type': type, if (name != null) 'name': name};

    final floor = FloorMap(
      section: const MapSection(path: 'x', label: 'T_1F'),
      nodes: {
        'node_0-10': {'x': 10 * s, 'y': 0, 'edges': [], 'wallTop': true},
        'node_0-11': {'x': 11 * s, 'y': 0, 'edges': [], 'wallTop': true},
        'node_0-12': {'x': 12 * s, 'y': 0, 'edges': [], 'doorTop': true},
      },
      cells: [
        // 部屋（名前つき）
        for (var x = 10; x < 14; x++)
          for (var y = 0; y < 3; y++) cell(x, y, CellType.room, '211講義室'),
        // 通路
        for (var x = 10; x < 14; x++) cell(x, 3, CellType.corridor),
        // 階段
        for (var x = 14; x < 16; x++)
          for (var y = 0; y < 4; y++) cell(x, y, CellType.stairs, '中央階段'),
        // 図の隅にある位置合わせの印（どこともつながっていない）
        for (var x = 0; x < 2; x++)
          for (var y = 40; y < 42; y++) cell(x, y, CellType.corridor),
      ],
      rooms: const [],
      roomCenters: const {'211講義室': Offset(120, 15)},
      entryIdByName: const {},
      destinationNames: const {},
    );
    final geo = FloorGeometry.build(floor);

    test('表示範囲に図の隅の印を含めない', () {
      expect(geo.extent.left, 10 * s);
      expect(geo.extent.bottom, 4 * s);
    });

    test('名前つきの区画をまとめ、種類を推し量る', () {
      final room = geo.roomByName['211講義室']!;
      expect(room.cellCount, 12);
      expect(room.category.kind, PlaceKind.classroom);
      expect(room.anchor, const Offset(120, 15));

      final stairs = geo.roomByName['中央階段']!;
      expect(stairs.category.kind, PlaceKind.stairs);
      expect(stairs.hatch, isNotNull);
    });

    test('タップした地点の区画名', () {
      expect(geo.nameAt(const Offset(105, 5)), '211講義室');
      expect(geo.nameAt(const Offset(145, 35)), '中央階段');
      expect(geo.nameAt(const Offset(105, 35)), isNull); // 通路
      expect(geo.nameAt(const Offset(5, 405)), isNull); // 取り除いた印
    });
  });
}
