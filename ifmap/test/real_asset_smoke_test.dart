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
import 'package:ifmap/routing/route_planner.dart';

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

  // 登録されているマップ全部を読み、形とフロアのつながりを確かめる。
  // 見取り図PDFから自動生成したフロア（ifmap_editor/tool/pdf_maps）が
  // 増えたので、1枚だけでなく全部を見ておく。
  group('登録されている全フロア', () {
    final parsedByLabel = <String, Map<String, dynamic>>{};

    setUpAll(() async {
      for (final s in AppConfig.mapSections) {
        parsedByLabel[s.label] = parseFloorJson(await rootBundle.loadString(s.path));
      }
    });

    test('どのフロアもノードと目的地がある', () {
      for (final s in AppConfig.mapSections) {
        final p = parsedByLabel[s.label]!;
        expect((p['nodes'] as Map), isNotEmpty, reason: s.label);
        expect((p['destinations'] as List), isNotEmpty, reason: s.label);
      }
    });

    test('別の建物の部屋へ、屋外を通って行ける', () {
      final nodesByLabel = {
        for (final e in parsedByLabel.entries)
          e.key: (e.value['nodes'] as Map).cast<String, dynamic>(),
      };
      final labels = AppConfig.mapSections.map((s) => s.label).toList();
      String idOf(String label, String name) =>
          (parsedByLabel[label]!['entryIdByName'] as Map)[name] as String;

      // 寮の2F → 本棟の2F、体育館 → 寮の4F
      for (final (from, fromName, to, toName) in [
        ('TAISHI_2F', '大志寮_2F_シャワー洗濯室', 'NITTC_2F', '221講義室'),
        ('GYM1_1F', '第1体育館_1F_小会議室', 'SOSHI_4F', '創志寮_4F_洗面(1)'),
      ]) {
        final request = RoutePlanRequest(
          nodesByLabel: nodesByLabel,
          sectionLabels: labels,
          startId: idOf(from, fromName),
          goalId: idOf(to, toName),
          startLabel: from,
          goalLabel: to,
        );
        final result = RoutePlanner.plan(request);
        expect(result.keys.first, from, reason: '$fromName → $toName');
        expect(result.keys.last, to, reason: '$fromName → $toName');
        expect(result.keys, contains('NITTC_ground_1F'));
        expect(RoutePlanner.planFromMessage(request.trimmed().toMessage()), result);
      }
    });

    test('同じ建物の上下の階は、同じ名前の階段か接続点でつながる', () {
      Set<String> stairs(String label) => {
            for (final v in (parsedByLabel[label]!['nodes'] as Map).values)
              if (v is Map && v['isStairs'] == true && v['name'] is String) v['name'] as String
          };
      bool hasConnector(String label) => (parsedByLabel[label]!['nodes'] as Map)
          .values
          .any((v) => v is Map && v['isConnector'] == true);

      final sections = AppConfig.mapSections.where((s) => !s.outdoor).toList();
      for (var i = 0; i + 1 < sections.length; i++) {
        final a = sections[i], b = sections[i + 1];
        if (a.buildingName != b.buildingName) continue;
        if (hasConnector(a.label) || hasConnector(b.label)) continue;
        expect(stairs(a.label).intersection(stairs(b.label)), isNotEmpty,
            reason: '${a.label} と ${b.label}');
      }
    });
  });
}
