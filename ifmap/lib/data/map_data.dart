// lib/data/map_data.dart
//
// マップJSONの読み込みと、検索に必要な索引づくりを担当する。
//
// JSONの形（ifmap_editor の JsonExporter と対になっている）:
//   {
//     "node_{行}-{列}": { x, y, edges[], name?, isStairs?, isConnector?,
//                         isOutdoor?, connectsToMap?, connectsToNode?,
//                         wallTop?..., doorTop?... },
//     ...
//     "_editorData": { bgImageBase64, cells[], rooms[], rows, cols }
//   }
//
// 注意: ノード側には type が書き出されていない（セル側にしかない）。
// 経路のチェックポイント判定はノードの type を見るので、
// 読み込み時にセルの type をノードへ写し込む。これをやらないと
// 「部屋に入る/出る」のチェックポイントが一切生成されない。
import 'dart:convert';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../config.dart';

/// セルの種別。ifmap_editor の MapCell.type と対応する。
class CellType {
  CellType._();
  static const int blank = 0;
  static const int corridor = 1;
  static const int room = 3; // 目的地 / QR設置場所
  static const int stairs = 4;
  static const int connector = 5; // 別棟・別フロアへの接続点
  static const int outdoor = 6;
  static const int decoration = 10;
}

/// 施設内の1地点への参照。
///
/// 名前だけで持ち回ると「1Fのトイレ」と「2Fのトイレ」を区別できず、
/// 別フロアの同名部屋へ誘導してしまう。必ずフロアとセットで扱う。
@immutable
class PlaceRef {
  final String name;
  final String label;
  const PlaceRef(this.name, this.label);

  @override
  bool operator ==(Object other) =>
      other is PlaceRef && other.name == name && other.label == label;

  @override
  int get hashCode => Object.hash(name, label);

  @override
  String toString() => '$name@$label';
}

/// 1フロア分のマップ。読み込み後は不変。
class FloorMap {
  final MapSection section;

  /// ノードID -> ノード。type はセルから写し込み済み。
  final Map<String, dynamic> nodes;

  /// 描画用のセル一覧（エディタの出力そのまま）。
  final List<dynamic> cells;

  /// 部屋名と中心座標の一覧（エディタの出力そのまま）。
  final List<dynamic> rooms;

  /// 部屋名 -> 中心座標(JSON-px)。
  final Map<String, Offset> roomCenters;

  /// 部屋名 -> その名前のノードのうち中心にいちばん近いもの。
  /// 経路計算の始点・終点はここから引く。
  final Map<String, String> entryIdByName;

  /// 目的地として選べる名前（階段・接続点は除く）。
  final Set<String> destinationNames;

  const FloorMap({
    required this.section,
    required this.nodes,
    required this.cells,
    required this.rooms,
    required this.roomCenters,
    required this.entryIdByName,
    required this.destinationNames,
  });

  String get label => section.label;

  /// 名前でもノードIDでも引ける。見つからなければ null。
  String? nodeIdOf(String nameOrId) {
    if (nodes.containsKey(nameOrId)) return nameOrId;
    return entryIdByName[nameOrId];
  }

  bool contains(String nameOrId) => nodeIdOf(nameOrId) != null;

  /// 描画用の中心座標。部屋なら部屋の中心、ノードならマスの中心。
  Offset? centerOf(String nameOrId) {
    final center = roomCenters[nameOrId];
    if (center != null) return center;
    final id = nodeIdOf(nameOrId);
    if (id == null) return null;
    final n = nodes[id];
    if (n is! Map) return null;
    return Offset(
      (n['x'] as num).toDouble() + AppConfig.cellCenter,
      (n['y'] as num).toDouble() + AppConfig.cellCenter,
    );
  }
}

/// 全フロアをまとめて持ち、フロアをまたいだ名前解決を行う。
class MapRepository {
  final Map<String, FloorMap> _floors = {};

  /// 名前・ノードID -> それを持つフロアラベル（mapSections の順）。
  final Map<String, List<String>> _labelsByName = {};

  /// 読み込み済みのフロアラベル。mapSections の順に並ぶ。
  List<String> get labels => _floors.keys.toList(growable: false);

  bool get isEmpty => _floors.isEmpty;

  FloorMap? floor(String label) => _floors[label];

  Map<String, Map<String, dynamic>> get nodesByLabel =>
      {for (final e in _floors.entries) e.key: e.value.nodes};

  /// その名前が存在するフロアをすべて返す。
  List<String> labelsOf(String nameOrId) => _labelsByName[nameOrId] ?? const [];

  /// その名前が属するフロア。
  ///
  /// [preferred] を渡すと、そのフロアに同名があればそちらを優先する。
  /// 「いま見ているフロアのトイレ」を選んだつもりが別階に飛ぶのを防ぐ。
  String? labelOf(String nameOrId, {String? preferred}) {
    final candidates = labelsOf(nameOrId);
    if (candidates.isEmpty) return null;
    if (preferred != null && candidates.contains(preferred)) return preferred;
    return candidates.first;
  }

  /// 名前からフロアつきの参照を作る。
  PlaceRef? resolve(String nameOrId, {String? preferred}) {
    final label = labelOf(nameOrId, preferred: preferred);
    return label == null ? null : PlaceRef(nameOrId, label);
  }

  /// 目的地候補。[label] を指定するとそのフロアだけに絞る。
  List<PlaceRef> destinations({String? label}) {
    final out = <PlaceRef>[];
    for (final f in _floors.values) {
      if (label != null && f.label != label) continue;
      for (final name in f.destinationNames) {
        out.add(PlaceRef(name, f.label));
      }
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  /// 読み込み済みのフロアを1件追加する。テストからも使う。
  void put(FloorMap floor) {
    _floors[floor.label] = floor;
    for (final key in floor.nodes.keys) {
      _labelsByName.putIfAbsent(key, () => []).add(floor.label);
    }
    for (final name in floor.entryIdByName.keys) {
      _labelsByName.putIfAbsent(name, () => []).add(floor.label);
    }
  }

  /// 全フロアを1枚ずつ読み込む。
  ///
  /// まとめて Future.wait せず逐次に処理するのは、Web では compute() が
  /// メインスレッドで同期実行されるため。1枚ずつ await を挟むことで
  /// 進捗表示を描画する隙間ができ、「真っ白のまま固まる」のを避けられる。
  /// [onFloorLoaded] は1枚読むたびに呼ばれる。
  Future<void> loadAll({
    List<MapSection> sections = AppConfig.mapSections,
    void Function(FloorMap floor, int loaded, int total)? onFloorLoaded,
    void Function(MapSection section, Object error)? onError,
  }) async {
    var loaded = 0;
    for (final section in sections) {
      try {
        final content = await rootBundle.loadString(section.path);
        final parsed = await compute(parseFloorJson, content);
        final floor = _floorFromParsed(section, parsed);
        put(floor);
        loaded++;
        onFloorLoaded?.call(floor, loaded, sections.length);
      } catch (e, st) {
        debugPrint('マップ読み込み失敗 ${section.path}: $e\n$st');
        onError?.call(section, e);
      }
      // 次のフロアを読む前に1フレーム譲る。
      await Future<void>.delayed(Duration.zero);
    }
  }
}

FloorMap _floorFromParsed(MapSection section, Map<String, dynamic> parsed) {
  final centers = (parsed['roomCenters'] as Map).map(
    (k, v) => MapEntry(k as String, Offset((v as List)[0] as double, v[1] as double)),
  );
  return FloorMap(
    section: section,
    nodes: (parsed['nodes'] as Map).cast<String, dynamic>(),
    cells: parsed['cells'] as List<dynamic>,
    rooms: parsed['rooms'] as List<dynamic>,
    roomCenters: centers,
    entryIdByName: (parsed['entryIdByName'] as Map).cast<String, String>(),
    destinationNames: (parsed['destinations'] as List).cast<String>().toSet(),
  );
}

/// compute() に渡すトップレベル関数。
///
/// 戻り値はプリミティブだけで構成する。Isolate 境界を越えるコストと
/// 送れる型の制約を気にしなくて済むようにするため。
@visibleForTesting
Map<String, dynamic> parseFloorJson(String content) {
  final full = jsonDecode(content) as Map<String, dynamic>;

  final editor = full['_editorData'];
  final cells = (editor is Map ? editor['cells'] as List<dynamic>? : null) ?? const [];
  final rooms = (editor is Map ? editor['rooms'] as List<dynamic>? : null) ?? const [];

  final nodes = <String, dynamic>{};
  for (final e in full.entries) {
    if (e.key == '_editorData') continue;
    nodes[e.key] = e.value;
  }

  // セルの type をノードへ写し込む。
  // ノードIDは node_{行}-{列}、セルは {x: 列, y: 行}。
  for (final c in cells) {
    if (c is! Map) continue;
    final cx = (c['x'] as num?)?.toInt();
    final cy = (c['y'] as num?)?.toInt();
    final type = (c['type'] as num?)?.toInt();
    if (cx == null || cy == null || type == null) continue;
    final node = nodes['node_$cy-$cx'];
    if (node is Map) node['type'] = type;
  }

  // 部屋の中心。
  final roomCenters = <String, List<double>>{};
  for (final r in rooms) {
    if (r is! Map) continue;
    final name = r['name'] as String?;
    final cx = (r['centerX'] as num?)?.toDouble();
    final cy = (r['centerY'] as num?)?.toDouble();
    if (name == null || name.isEmpty || cx == null || cy == null) continue;
    roomCenters[name] = [cx, cy];
  }

  // 名前 -> 代表ノード（部屋の中心にいちばん近いもの）と、目的地候補。
  final entryIdByName = <String, String>{};
  final bestDistance = <String, double>{};
  final destinations = <String>{};

  for (final e in nodes.entries) {
    final v = e.value;
    if (v is! Map) continue;
    final name = v['name'] as String?;
    if (name == null || name.isEmpty) continue;

    final isStairs = v['isStairs'] == true;
    final isConnector = v['isConnector'] == true;
    if (!isStairs && !isConnector) destinations.add(name);

    final center = roomCenters[name];
    double distance = 0;
    if (center != null) {
      final nx = (v['x'] as num).toDouble() + AppConfig.cellCenter;
      final ny = (v['y'] as num).toDouble() + AppConfig.cellCenter;
      final dx = nx - center[0];
      final dy = ny - center[1];
      distance = dx * dx + dy * dy;
    }
    final best = bestDistance[name];
    if (best == null || distance < best) {
      bestDistance[name] = distance;
      entryIdByName[name] = e.key;
    }
  }

  return {
    'nodes': nodes,
    'cells': cells,
    'rooms': rooms,
    'roomCenters': roomCenters,
    'entryIdByName': entryIdByName,
    'destinations': destinations.toList(),
  };
}
