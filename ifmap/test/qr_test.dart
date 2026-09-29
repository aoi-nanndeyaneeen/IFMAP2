// エディタで置いたQRコード（?qr=ID）を読んだときの動き。
import 'package:flutter_test/flutter_test.dart';
import 'package:ifmap/config.dart';
import 'package:ifmap/data/map_data.dart';
import 'package:ifmap/navigation/navigation_controller.dart';
import 'package:ifmap/sensors/step_tracker.dart';

Map<String, dynamic> _node(int cellX, int cellY,
        {List<String> edges = const [],
        String? name,
        int type = CellType.corridor,
        Map<String, dynamic> extra = const {}}) =>
    {
      'x': cellX * AppConfig.pxPerCell,
      'y': cellY * AppConfig.pxPerCell,
      'edges': edges,
      'type': type,
      if (name != null) 'name': name,
      ...extra,
    };

FloorMap _floor(String label, Map<String, dynamic> nodes) {
  final entry = <String, String>{};
  for (final e in nodes.entries) {
    final name = (e.value as Map)['name'] as String?;
    if (name != null) entry.putIfAbsent(name, () => e.key);
  }
  return FloorMap(
    section: MapSection(path: 'x', label: label),
    nodes: nodes,
    cells: const [],
    rooms: const [],
    roomCenters: const {},
    entryIdByName: entry,
    destinationNames: entry.keys.toSet(),
  );
}

const _f1 = 'NITTC_1F';

/// 受付(0,0) -- 廊下を東へ10マス -- 電算室(10,0)
/// 廊下の途中 (5,0) に QR「qrmid」、経路から1マス外れた (7,1) に「qrside」、
/// 経路から遠い (5,20) に「qrfar」。
MapRepository _repository() {
  final nodes = <String, dynamic>{};
  for (var x = 0; x <= 10; x++) {
    nodes['h$x'] = _node(x, 0,
        edges: [if (x > 0) 'h${x - 1}', if (x < 10) 'h${x + 1}'],
        name: x == 0 ? '受付' : (x == 10 ? '電算室' : null));
  }
  (nodes['h5'] as Map)['qrId'] = 'qrmid';
  (nodes['h5'] as Map)['qrMemo'] = '廊下の中ほど';
  nodes['side'] = _node(7, 1, extra: {'qrId': 'qrside'});
  nodes['far'] = _node(5, 20, extra: {'qrId': 'qrfar', 'qrMemo': '遠くの部屋'});
  return MapRepository()..put(_floor(_f1, nodes));
}

void main() {
  group('MapRepository', () {
    test('ノードの qrId から設置位置を引ける', () {
      final spot = _repository().qrSpot('qrmid')!;
      expect(spot.label, _f1);
      expect(spot.nodeId, 'h5');
      expect(spot.memo, '廊下の中ほど');
    });

    test('登録されていないIDは null', () {
      expect(_repository().qrSpot('nothing'), isNull);
    });
  });

  group('StepTracker.snapToNode', () {
    late StepTracker tracker;
    final nodes = _repository().floor(_f1)!.nodes;
    final path = [for (var x = 0; x <= 10; x++) 'h$x'];

    setUp(() => tracker = StepTracker()..setRoute(path, nodes));
    tearDown(() => tracker.dispose());

    test('経路上のノードならそこまで進んだことにする', () {
      expect(tracker.snapToNode('h5'), isNotNull);
      expect(tracker.traveledPx, 50);
    });

    test('経路のすぐ脇なら最寄りの経路上の点に合わせる', () {
      // (7,1) は経路 (7,0) から 10px。許容 3m=60px 以内。
      expect(tracker.snapToNode('side'), isNotNull);
      expect(tracker.traveledPx, 70);
    });

    test('経路から離れていれば何もせず null', () {
      expect(tracker.snapToNode('far'), isNull);
      expect(tracker.traveledPx, 0);
    });

    test('数えすぎていた場合は手前に戻す', () {
      tracker.snapToNode('h7');
      tracker.snapToNode('h5');
      expect(tracker.traveledPx, 50);
    });
  });

  group('NavigationController.applyQr', () {
    late NavigationController c;
    late List<AppMessage> messages;

    setUp(() {
      c = NavigationController(repository: _repository());
      messages = [];
      c.messages.listen(messages.add);
    });
    tearDown(() => c.dispose());

    test('案内していなければ、そこを現在地にする', () async {
      await c.applyQr('qrmid');
      expect(c.start, const PlaceRef('h5', _f1));
      await Future<void>.delayed(Duration.zero);
      expect(messages.last.text, contains('廊下の中ほど'));
    });

    test('案内中で経路上なら、経路を引き直さずに位置だけ合わせる', () async {
      await c.setStartByName('受付');
      await c.setGoal(const PlaceRef('電算室', _f1));
      final pathBefore = c.currentPath;

      await c.applyQr('qrmid');
      await Future<void>.delayed(Duration.zero);

      // 進んだ距離そのものは StepTracker.snapToNode のテストで見ている。
      // （traveledPx は initialize() で張るストリーム経由で届くが、
      //  このテストでは initialize() を呼ばない）
      expect(c.start, const PlaceRef('受付', _f1));
      expect(c.currentPath, pathBefore);
      expect(messages.last.text, '「廊下の中ほど」で現在地を補正しました');
    });

    test('案内中でも経路から離れていれば、そこから引き直す', () async {
      await c.setStartByName('受付');
      await c.setGoal(const PlaceRef('電算室', _f1));

      await c.applyQr('qrfar');

      expect(c.start, const PlaceRef('far', _f1));
      expect(c.goal, const PlaceRef('電算室', _f1));
    });

    test('登録されていないIDは知らせて何も変えない', () async {
      await c.applyQr('nothing');
      await Future<void>.delayed(Duration.zero);
      expect(c.start, isNull);
      expect(messages.single.kind, MessageKind.error);
    });

    test('スキャナで読んだURLの ?qr= を拾う', () async {
      await c.handleScannedCode(
          'https://aoi-nanndeyaneeen.github.io/IFMAP2/?qr=qrmid');
      expect(c.start, const PlaceRef('h5', _f1));
    });

    test('?qr= がなければ従来どおり名前として扱う', () async {
      await c.handleScannedCode('受付');
      expect(c.start, const PlaceRef('受付', _f1));
    });
  });
}
