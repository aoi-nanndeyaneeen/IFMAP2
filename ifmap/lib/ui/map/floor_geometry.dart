// lib/ui/map/floor_geometry.dart
//
// マス目のマップを、描くための図形（輪郭の折れ線）に組み直す。
//
// エディタが出すのは 0.5m 四方のマスの集まりなので、そのまま四角を
// 並べて塗ると「ドット絵」になる。ここでは
//   1. 同じ部屋（同じ種類・同じ名前）のマスをまとめ、
//   2. その外周をたどって輪郭線にし（輪郭追跡）、
//   3. マス目の段々を少しだけならす（Douglas-Peucker）
// ことで、建築図面のような面と線に変える。壁と扉はノードの印から
// 線分を作り、一直線に並ぶものはつなげる。
//
// 一度作れば変わらないので FloorMap ごとに1回だけ作って使い回す。
import 'dart:math' as math;
import 'dart:ui';

import '../../config.dart';
import '../../data/map_data.dart';
import '../place_category.dart';

/// 名前のついた区画1つ（部屋・階段・建物など）。
class RoomShape {
  final String name;
  final int type;
  final PlaceCategory category;

  /// 塗りと輪郭（JSON-px）。
  final Path path;
  final Rect bounds;

  /// マスの数。ラベルの優先度（広い部屋ほど先に置く）に使う。
  final int cellCount;

  /// ラベルを置く点（JSON-px）。
  final Offset anchor;

  /// 階段の踏み面を表す線（JSON-px）。階段以外は null。
  final Path? hatch;

  const RoomShape({
    required this.name,
    required this.type,
    required this.category,
    required this.path,
    required this.bounds,
    required this.cellCount,
    required this.anchor,
    this.hatch,
  });

  bool get isConnector => type == CellType.connector;
  bool get isStairs => type == CellType.stairs;
}

class FloorGeometry {
  /// マスのある範囲（JSON-px）。最初の表示位置を決めるのに使う。
  final Rect extent;

  /// 建物の床（屋内のマスをすべて合わせたもの）。影と外周線に使う。
  final Path footprint;
  final Path corridors;
  final Path outdoor;

  /// 名前のない部屋・装飾（屋外図の建物など）も含む。塗る順に並ぶ。
  final List<RoomShape> rooms;

  /// 名前 -> 区画。名前のない区画は入らない。
  final Map<String, RoomShape> roomByName;

  final Path walls;
  final Path doors;

  /// マス -> そのマスの区画名。タップした場所の特定に使う。
  final Map<int, String> _nameByCell;

  const FloorGeometry._({
    required this.extent,
    required this.footprint,
    required this.corridors,
    required this.outdoor,
    required this.rooms,
    required this.roomByName,
    required this.walls,
    required this.doors,
    required Map<int, String> nameByCell,
  }) : _nameByCell = nameByCell;

  static final Expando<FloorGeometry> _cache = Expando('FloorGeometry');

  static FloorGeometry of(FloorMap floor) =>
      _cache[floor] ??= FloorGeometry.build(floor);

  /// その地点（JSON-px）のマスについている区画名。なければ null。
  String? nameAt(Offset p) {
    final cx = (p.dx / AppConfig.pxPerCell).floor();
    final cy = (p.dy / AppConfig.pxPerCell).floor();
    if (cx < 0 || cy < 0) return null;
    return _nameByCell[_key(cx, cy)];
  }

  static int _key(int x, int y) => (y << 16) | x;

  static FloorGeometry build(FloorMap floor) {
    const s = AppConfig.pxPerCell;

    // ── マスの読み取り ─────────────────────────────────────────
    final typeOf = <int, int>{};
    final nameOf = <int, String>{};
    for (final c in floor.cells) {
      if (c is! Map) continue;
      final type = (c['type'] as num?)?.toInt() ?? CellType.blank;
      if (type == CellType.blank) continue;
      final x = (c['x'] as num).toInt();
      final y = (c['y'] as num).toInt();
      if (x < 0 || y < 0) continue;
      final k = _key(x, y);
      typeOf[k] = type;
      final name = c['name'];
      if (name is String && name.isNotEmpty) nameOf[k] = name;
    }

    // どこともつながっていない名前のない小さな塊（図の四隅に置かれた
    // 位置合わせの印など）は描かず、表示範囲にも含めない。含めると
    // 全体表示が小さくなり、地図の端にごみのような四角が出る。
    _dropStrayClusters(typeOf, nameOf);

    var minX = 1 << 30, minY = 1 << 30, maxX = -1, maxY = -1;
    for (final k in typeOf.keys) {
      final x = k & 0xFFFF, y = k >> 16;
      minX = math.min(minX, x);
      minY = math.min(minY, y);
      maxX = math.max(maxX, x);
      maxY = math.max(maxY, y);
    }
    final extent = maxX < 0
        ? const Rect.fromLTWH(0, 0, 1000, 1000)
        : Rect.fromLTRB(minX * s, minY * s, (maxX + 1) * s, (maxY + 1) * s);

    // ── 区画ごとにマスをまとめる ─────────────────────────────────
    final footprintCells = <int>{};
    final corridorCells = <int>{};
    final outdoorCells = <int>{};
    final groups = <(int, String), Set<int>>{};
    for (final e in typeOf.entries) {
      final type = e.value;
      switch (type) {
        case CellType.corridor:
          corridorCells.add(e.key);
          footprintCells.add(e.key);
        case CellType.outdoor:
          outdoorCells.add(e.key);
        case CellType.room:
        case CellType.stairs:
        case CellType.connector:
          footprintCells.add(e.key);
          groups.putIfAbsent((type, nameOf[e.key] ?? ''), () => {}).add(e.key);
        case CellType.decoration:
          groups.putIfAbsent((type, nameOf[e.key] ?? ''), () => {}).add(e.key);
        default:
          break;
      }
    }

    final rooms = <RoomShape>[];
    final roomByName = <String, RoomShape>{};
    for (final entry in groups.entries) {
      final (type, name) = entry.key;
      final cells = entry.value;
      final loops = traceContours(cells);
      if (loops.isEmpty) continue;
      final path = _pathOf(loops, smooth: true);
      final bounds = path.getBounds();

      final PlaceCategory category;
      if (type == CellType.decoration) {
        category = PlaceCategories.building;
      } else if (type == CellType.stairs) {
        final c = PlaceCategories.of(name);
        category = c.kind == PlaceKind.elevator ? c : PlaceCategories.stairs;
      } else {
        category = PlaceCategories.of(name);
      }

      final anchor = floor.roomCenters[name] ?? _interiorPoint(cells, bounds);
      final shape = RoomShape(
        name: name,
        type: type,
        category: category,
        path: path,
        bounds: bounds,
        cellCount: cells.length,
        anchor: anchor,
        hatch: type == CellType.stairs ? _stairHatch(cells, bounds) : null,
      );
      rooms.add(shape);
      if (name.isNotEmpty) {
        // 同じ名前が別の種類にもある場合は、広いほうを代表にする。
        final prev = roomByName[name];
        if (prev == null || prev.cellCount < shape.cellCount) {
          roomByName[name] = shape;
        }
      }
    }
    // 広いものから塗ると、狭い部屋が広い部屋に隠れない。
    rooms.sort((a, b) => b.cellCount.compareTo(a.cellCount));

    // ── 壁と扉 ──────────────────────────────────────────────────
    final wallH = <int, List<int>>{}, wallV = <int, List<int>>{};
    final doorH = <int, List<int>>{}, doorV = <int, List<int>>{};
    for (final n in floor.nodes.values) {
      if (n is! Map) continue;
      final x = ((n['x'] as num) / s).round();
      final y = ((n['y'] as num) / s).round();
      void add(Map<int, List<int>> m, int line, int at) =>
          m.putIfAbsent(line, () => []).add(at);
      if (n['wallTop'] == true) add(wallH, y, x);
      if (n['wallBottom'] == true) add(wallH, y + 1, x);
      if (n['wallLeft'] == true) add(wallV, x, y);
      if (n['wallRight'] == true) add(wallV, x + 1, y);
      if (n['doorTop'] == true) add(doorH, y, x);
      if (n['doorBottom'] == true) add(doorH, y + 1, x);
      if (n['doorLeft'] == true) add(doorV, x, y);
      if (n['doorRight'] == true) add(doorV, x + 1, y);
    }

    return FloorGeometry._(
      extent: extent,
      footprint: _pathOf(traceContours(footprintCells), smooth: true),
      corridors: _pathOf(traceContours(corridorCells), smooth: false),
      outdoor: _pathOf(traceContours(outdoorCells), smooth: true),
      rooms: rooms,
      roomByName: roomByName,
      walls: _segments(wallH, wallV, inset: 0),
      doors: _segments(doorH, doorV, inset: 0.12),
      nameByCell: nameOf,
    );
  }

  static const int _strayMaxCells = 40;

  static void _dropStrayClusters(Map<int, int> typeOf, Map<int, String> nameOf) {
    final seen = <int>{};
    final drop = <int>[];
    for (final start in typeOf.keys) {
      if (!seen.add(start)) continue;
      final cluster = <int>[start];
      var named = false;
      for (var i = 0; i < cluster.length; i++) {
        final k = cluster[i];
        if (nameOf.containsKey(k)) named = true;
        final x = k & 0xFFFF, y = k >> 16;
        for (final n in [_key(x + 1, y), _key(x, y + 1), if (x > 0) _key(x - 1, y), if (y > 0) _key(x, y - 1)]) {
          if (typeOf.containsKey(n) && seen.add(n)) cluster.add(n);
        }
      }
      if (!named && cluster.length <= _strayMaxCells) drop.addAll(cluster);
    }
    drop.forEach(typeOf.remove);
  }

  /// 同じ線上に並ぶ1マスぶんの線分をつなげて Path にする。
  /// [inset] はマスの単位で、線分の両端を縮める量（扉の枠を残すため）。
  static Path _segments(Map<int, List<int>> horizontal,
      Map<int, List<int>> vertical,
      {required double inset}) {
    const s = AppConfig.pxPerCell;
    final path = Path();
    void emit(Map<int, List<int>> lines, bool isHorizontal) {
      for (final e in lines.entries) {
        final at = e.value.toSet().toList()..sort();
        var runStart = at.first, prev = at.first;
        void flush() {
          final a = (runStart + inset) * s, b = (prev + 1 - inset) * s;
          final line = e.key * s;
          if (isHorizontal) {
            path
              ..moveTo(a, line)
              ..lineTo(b, line);
          } else {
            path
              ..moveTo(line, a)
              ..lineTo(line, b);
          }
        }

        for (final v in at.skip(1)) {
          if (v == prev + 1) {
            prev = v;
            continue;
          }
          flush();
          runStart = prev = v;
        }
        flush();
      }
    }

    emit(horizontal, true);
    emit(vertical, false);
    return path;
  }

  /// 階段の踏み面。区画の短い辺に平行な線を1マスおきに引く
  /// （マスの境目の線のうち、両側が階段のものだけ）。
  static Path _stairHatch(Set<int> cells, Rect bounds) {
    final treadsVertical = bounds.width >= bounds.height;
    final lines = <int, List<int>>{};
    for (final k in cells) {
      final x = k & 0xFFFF, y = k >> 16;
      if (treadsVertical) {
        if (cells.contains(_key(x - 1, y))) {
          lines.putIfAbsent(x, () => []).add(y);
        }
      } else if (cells.contains(_key(x, y - 1))) {
        lines.putIfAbsent(y, () => []).add(x);
      }
    }
    return treadsVertical
        ? _segments(const {}, lines, inset: 0.15)
        : _segments(lines, const {}, inset: 0.15);
  }

  /// 区画の内側にあることが確かな点。部屋の中心が登録されていない
  /// 区画のラベル位置に使う。重心に最も近いマスの中心。
  static Offset _interiorPoint(Set<int> cells, Rect bounds) {
    const s = AppConfig.pxPerCell;
    final c = bounds.center;
    var best = double.infinity;
    var point = c;
    for (final k in cells) {
      final p = Offset(((k & 0xFFFF) + 0.5) * s, ((k >> 16) + 0.5) * s);
      final d = (p - c).distanceSquared;
      if (d < best) {
        best = d;
        point = p;
      }
    }
    return point;
  }

  static Path _pathOf(List<List<Offset>> loops, {required bool smooth}) {
    const s = AppConfig.pxPerCell;
    final path = Path()..fillType = PathFillType.evenOdd;
    for (final raw in loops) {
      final loop = smooth ? simplifyLoop(raw, 0.75) : raw;
      path.moveTo(loop.first.dx * s, loop.first.dy * s);
      for (final p in loop.skip(1)) {
        path.lineTo(p.dx * s, p.dy * s);
      }
      path.close();
    }
    return path;
  }
}

/// マスの集まりの外周（穴の縁も含む）を、マスの角を頂点とする閉じた
/// 折れ線の一覧で返す。座標はマス単位。一直線に並ぶ頂点は省く。
///
/// 各マスの4辺のうち、隣が集まりに入っていない辺を「集まりを右手に見る
/// 向き」で並べ、端点どうしをつないでいく。角で1点だけ接する2マスでは
/// 行き先が2つになるので、右折を優先して別々の輪にする。
List<List<Offset>> traceContours(Set<int> cells) {
  if (cells.isEmpty) return const [];
  bool has(int x, int y) =>
      x >= 0 && y >= 0 && cells.contains(FloorGeometry._key(x, y));
  int vkey(int x, int y) => (y << 16) | x;

  // 向き: 0 = +x, 1 = +y, 2 = -x, 3 = -y （y は下向き）
  const dx = [1, 0, -1, 0], dy = [0, 1, 0, -1];
  final fromX = <int>[], fromY = <int>[], dir = <int>[];
  final outgoing = <int, List<int>>{};
  void addEdge(int x, int y, int d) {
    final i = dir.length;
    fromX.add(x);
    fromY.add(y);
    dir.add(d);
    outgoing.putIfAbsent(vkey(x, y), () => []).add(i);
  }

  for (final k in cells) {
    final x = k & 0xFFFF, y = k >> 16;
    if (!has(x, y - 1)) addEdge(x, y, 0);
    if (!has(x + 1, y)) addEdge(x + 1, y, 1);
    if (!has(x, y + 1)) addEdge(x + 1, y + 1, 2);
    if (!has(x - 1, y)) addEdge(x, y + 1, 3);
  }

  final used = List<bool>.filled(dir.length, false);
  final loops = <List<Offset>>[];
  for (var first = 0; first < dir.length; first++) {
    if (used[first]) continue;
    final loop = <Offset>[];
    var e = first;
    used[e] = true;
    while (true) {
      final ex = fromX[e] + dx[dir[e]], ey = fromY[e] + dy[dir[e]];
      final candidates = outgoing[vkey(ex, ey)] ?? const <int>[];
      int? next;
      var bestRank = 99;
      for (final c in candidates) {
        if (used[c] && c != first) continue;
        // 右折 > 直進 > 左折
        final turn = (dir[c] - dir[e] + 4) % 4;
        final rank = switch (turn) { 1 => 0, 0 => 1, 3 => 2, _ => 3 };
        if (rank < bestRank) {
          bestRank = rank;
          next = c;
        }
      }
      if (next == null) break; // 壊れた輪。ここまでで閉じる。
      if (dir[next] != dir[e]) loop.add(Offset(ex.toDouble(), ey.toDouble()));
      if (next == first) break;
      used[next] = true;
      e = next;
    }
    if (loop.length >= 3) loops.add(loop);
  }
  return loops;
}

/// 閉じた折れ線の Douglas-Peucker 単純化。[tolerance] はマス単位。
/// 1マスずつの段々（斜めの縁）は斜めの直線にならし、
/// 1マス以上の出っ張り・へこみは残す。
List<Offset> simplifyLoop(List<Offset> loop, double tolerance) {
  if (loop.length < 5) return loop;
  // 起点から最も遠い点で2つに分け、それぞれを開いた折れ線として扱う。
  var far = 0;
  var farD = -1.0;
  for (var i = 1; i < loop.length; i++) {
    final d = (loop[i] - loop[0]).distanceSquared;
    if (d > farD) {
      farD = d;
      far = i;
    }
  }
  final keep = List<bool>.filled(loop.length + 1, false);
  final pts = [...loop, loop.first];
  keep[0] = keep[far] = keep[pts.length - 1] = true;
  _dp(pts, 0, far, tolerance, keep);
  _dp(pts, far, pts.length - 1, tolerance, keep);
  final out = <Offset>[
    for (var i = 0; i < pts.length - 1; i++)
      if (keep[i]) pts[i],
  ];
  return out.length >= 3 ? out : loop;
}

void _dp(List<Offset> p, int first, int last, double tol, List<bool> keep) {
  if (last - first < 2) return;
  final a = p[first], b = p[last];
  final len = (b - a).distance;
  var maxD = -1.0;
  var maxI = -1;
  for (var i = first + 1; i < last; i++) {
    final d = len == 0
        ? (p[i] - a).distance
        : ((b.dx - a.dx) * (a.dy - p[i].dy) - (a.dx - p[i].dx) * (b.dy - a.dy))
                .abs() /
            len;
    if (d > maxD) {
      maxD = d;
      maxI = i;
    }
  }
  if (maxD > tol) {
    keep[maxI] = true;
    _dp(p, first, maxI, tol, keep);
    _dp(p, maxI, last, tol, keep);
  }
}
