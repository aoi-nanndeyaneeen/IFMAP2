// lib/data/campus_index.dart
//
// 「どの建物のどの階にどの部屋があるか」の索引（assets/campus_index.json）。
//
// マップのJSONは階ごとに分かれていて、部屋がどの建物に属するかは書かれて
// いない。検索で「建物から探す」ために、区域 / 建物 / 階 / 部屋 の階層を
// 別ファイルに持っている（tool/pdf_maps/build_index.py が書く）。
// 部屋の id はマップJSONのノード名（PlaceRef.name）と同じ。
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../config.dart';
import 'map_data.dart';

/// 索引の中の部屋1つ。
@immutable
class IndexedRoom {
  /// 画面に出す短い名前（例: 食堂）。建物名・階の部分を含まない。
  final String name;

  /// 場所への参照。name がマップ上のノード名、label がフロア。
  final PlaceRef place;
  final String floor;
  const IndexedRoom(this.name, this.place, this.floor);
}

/// 建物1つ。
class IndexedBuilding {
  final String name;

  /// 所属する区域（校舎・学寮など）。
  final String area;

  /// 階ごとの部屋。上の階が後ろに来る順（索引の並び）。
  final Map<String, List<IndexedRoom>> roomsByFloor;

  /// 階がない建物（図書館・プールなど）が、それ自体マップ上の場所として
  /// 引けるときの参照。
  final PlaceRef? self;

  IndexedBuilding(this.name, this.area, this.roomsByFloor, {this.self});

  List<IndexedRoom> get rooms => [for (final l in roomsByFloor.values) ...l];

  int get roomCount => roomsByFloor.values.fold(0, (n, l) => n + l.length);

  /// 探せるものが何もない（地図に載っていない）建物。
  bool get isEmpty => roomCount == 0 && self == null;
}

class IndexedArea {
  final String name;
  final List<IndexedBuilding> buildings;
  const IndexedArea(this.name, this.buildings);
}

class CampusIndex {
  final List<IndexedArea> areas;

  /// (フロア, ノード名) -> その部屋。
  final Map<(String, String), (IndexedBuilding, IndexedRoom)> _lookup;

  CampusIndex._(this.areas, this._lookup);

  static final empty = CampusIndex._(const [], const {});

  /// 探せるものがある建物だけを区域ごとに。
  List<IndexedArea> get visibleAreas => [
        for (final a in areas)
          if (a.buildings.any((b) => !b.isEmpty))
            IndexedArea(a.name, [for (final b in a.buildings) if (!b.isEmpty) b]),
      ];

  IndexedBuilding? buildingOf(PlaceRef p) => _lookup[(p.label, p.name)]?.$1;

  /// 索引にある短い名前。なければ null。
  String? roomNameOf(PlaceRef p) => _lookup[(p.label, p.name)]?.$2.name;

  static Future<CampusIndex> load(MapRepository repo,
      {String path = 'assets/campus_index.json'}) async {
    try {
      final text = await rootBundle.loadString(path);
      return parse(text, repo);
    } catch (e) {
      // 索引がなくても検索は動く（建物から探す、が出ないだけ）。
      debugPrint('campus_index の読み込みに失敗: $e');
      return parseMaps(repo, const []);
    }
  }

  @visibleForTesting
  static CampusIndex parse(String json, MapRepository repo) {
    final root = jsonDecode(json) as Map<String, dynamic>;
    final areas = <IndexedArea>[];
    final lookup = <(String, String), (IndexedBuilding, IndexedRoom)>{};
    final covered = <String>{};

    IndexedBuilding? building(Map b, String area) {
      final name = b['name'] as String;
      final byFloor = <String, List<IndexedRoom>>{};
      for (final f in (b['floors'] as List? ?? const [])) {
        final label = f['label'] as String;
        final floor = f['floor'] as String;
        for (final r in (f['rooms'] as List)) {
          final id = r['id'] as String;
          // 読み込めていないフロア・消えた部屋は出さない（選んでも行けない）。
          if (repo.floor(label) == null || repo.floor(label)!.nodeIdOf(id) == null) continue;
          byFloor.putIfAbsent(floor, () => []).add(
              IndexedRoom(r['name'] as String, PlaceRef(id, label), floor));
        }
        covered.add(label);
      }
      // 屋外の図に同じ名前の場所があれば、建物そのもの（入口側）も目的地に
      // できる。階のない建物（図書館・プールなど）はこれだけが目的地になる。
      final outdoor = repo.resolve(name);
      final isOutdoor =
          outdoor != null && AppConfig.sectionOf(outdoor.label)?.outdoor == true;
      PlaceRef? self;
      if (byFloor.isEmpty) {
        self = outdoor;
      } else if (isOutdoor) {
        final floors = {
          '屋外': [IndexedRoom(name, outdoor, '屋外')],
          ...byFloor,
        };
        byFloor
          ..clear()
          ..addAll(floors);
      }
      final out = IndexedBuilding(name, area, byFloor, self: self);
      for (final room in out.rooms) {
        lookup[(room.place.label, room.place.name)] = (out, room);
      }
      if (self != null) {
        lookup[(self.label, self.name)] = (out, IndexedRoom(name, self, '屋外'));
      }
      return out;
    }

    for (final a in (root['areas'] as List)) {
      final name = a['name'] as String;
      areas.add(IndexedArea(name, [
        for (final b in (a['buildings'] as List))
          if (building(b as Map, name) case final x?) x,
      ]));
    }

    final un = root['unassigned'];
    if (un is Map) {
      final b = building(un, '校舎');
      if (b != null && !b.isEmpty) {
        // 「棟の特定できない部屋」は校舎の区域の末尾に入れる。
        final i = areas.indexWhere((a) => a.name == '校舎');
        if (i >= 0) {
          areas[i] = IndexedArea(areas[i].name, [...areas[i].buildings, b]);
        } else {
          areas.add(IndexedArea('校舎', [b]));
        }
      }
    }

    // 索引に載っていないマップ（自宅など）は、1建物として足す。
    final extra = parseMaps(repo, covered);
    areas.addAll(extra.areas);
    lookup.addAll(extra._lookup);
    return CampusIndex._(areas, lookup);
  }

  /// 索引に載っていないフロアを、mapSections の建物名でまとめる。
  static CampusIndex parseMaps(MapRepository repo, Iterable<String> covered) {
    final skip = covered.toSet();
    final byBuilding = <String, Map<String, List<IndexedRoom>>>{};
    for (final s in AppConfig.mapSections) {
      if (s.outdoor || skip.contains(s.label) || repo.floor(s.label) == null) continue;
      for (final p in repo.destinations(label: s.label)) {
        byBuilding
            .putIfAbsent(s.buildingName, () => {})
            .putIfAbsent(s.floorDisplayName, () => [])
            .add(IndexedRoom(p.name, p, s.floorDisplayName));
      }
    }
    final buildings = <IndexedBuilding>[];
    final lookup = <(String, String), (IndexedBuilding, IndexedRoom)>{};
    for (final e in byBuilding.entries) {
      final b = IndexedBuilding(e.key, 'その他のマップ', e.value);
      buildings.add(b);
      for (final r in b.rooms) {
        lookup[(r.place.label, r.place.name)] = (b, r);
      }
    }
    return CampusIndex._(
        buildings.isEmpty ? const [] : [IndexedArea('その他のマップ', buildings)], lookup);
  }
}
