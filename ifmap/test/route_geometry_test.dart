// 経路を線として扱う計算（表示用にならした線・進んだ位置・進む向き）。
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ifmap/config.dart';
import 'package:ifmap/navigation/route_geometry.dart';

/// マス座標の並びから、ノードとその ID の並びを作る。
(List<String>, Map<String, dynamic>) _path(List<(int, int)> cells) {
  final ids = <String>[];
  final nodes = <String, dynamic>{};
  for (final (x, y) in cells) {
    final id = 'node_$y-$x';
    ids.add(id);
    nodes[id] = {'x': x * AppConfig.pxPerCell, 'y': y * AppConfig.pxPerCell};
  }
  return (ids, nodes);
}

void main() {
  // 東へ3マス進んでから南へ2マス
  final (ids, nodes) = _path([(0, 0), (1, 0), (2, 0), (3, 0), (3, 1), (3, 2)]);
  final geo = RouteGeometry.build(ids, nodes)!;
  const c = AppConfig.cellCenter;

  test('長さは経路に沿って測る', () {
    expect(geo.length, 50);
  });

  test('進んだ距離の点', () {
    expect(geo.pointAt(0), const Offset(c, c));
    expect(geo.pointAt(15), const Offset(15 + c, c));
    expect(geo.pointAt(40), const Offset(30 + c, 10 + c));
    expect(geo.pointAt(999), geo.display.last);
  });

  test('歩き終えた部分とこれからの部分は、その点でつながる', () {
    final done = geo.polylineUntil(40);
    final rest = geo.polylineFrom(40);
    expect(done.last, rest.first);
    expect(done.first, geo.display.first);
    expect(rest.last, geo.display.last);
  });

  test('進む向き（地図の上が0の時計回り）', () {
    expect(geo.headingAt(0, lookahead: 10), closeTo(math.pi / 2, 1e-9)); // 東
    expect(geo.headingAt(45, lookahead: 10), closeTo(math.pi, 1e-9)); // 南
    // 終点では最後の区間の向き
    expect(geo.headingAt(50), closeTo(math.pi, 1e-9));
  });

  test('1マスのがたつきは表示ではならす', () {
    final (ids2, nodes2) = _path([
      for (var x = 0; x < 10; x++) (x, 0),
      for (var x = 10; x < 20; x++) (x, 1),
    ]);
    final g = RouteGeometry.build(ids2, nodes2)!;
    expect(g.display.length, 2);
    expect(g.length, greaterThan(190));
  });

  test('部屋の中心からの引き出し線は距離に数えない', () {
    final g = RouteGeometry.build(ids, nodes,
        head: const Offset(-40, c), tail: const Offset(30 + c, 60))!;
    expect(g.length, 50);
    expect(g.display.first, const Offset(-40, c));
    expect(g.display.last, const Offset(30 + c, 60));
    expect(g.pointAt(0), const Offset(c, c));
  });
}
