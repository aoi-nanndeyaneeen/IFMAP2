import 'package:flutter_test/flutter_test.dart';
import 'package:ifmap/routing/route_calculator.dart';

/// 格子のノードを手で組み立てる。
/// 座標は JSON と同じく「マス番号 × pxPerCell」。
Map<String, dynamic> _node(int x, int y, List<String> edges,
        {Map<String, dynamic>? extra}) =>
    {'x': x * 10, 'y': y * 10, 'edges': edges, ...?extra};

void main() {
  group('dijkstra', () {
    // a - b - c
    //     |
    //     d
    final nodes = <String, dynamic>{
      'a': _node(0, 0, ['b']),
      'b': _node(1, 0, ['a', 'c', 'd']),
      'c': _node(2, 0, ['b']),
      'd': _node(1, 1, ['b']),
      'lonely': _node(9, 9, <String>[]),
    };

    test('隣接するノードをたどって最短経路を返す', () {
      expect(RouteCalculator.dijkstra('a', 'c', nodes), ['a', 'b', 'c']);
    });

    test('始点と終点が同じなら1要素', () {
      expect(RouteCalculator.dijkstra('a', 'a', nodes), ['a']);
    });

    test('到達できなければ空', () {
      expect(RouteCalculator.dijkstra('a', 'lonely', nodes), isEmpty);
    });

    test('存在しないノードなら空', () {
      expect(RouteCalculator.dijkstra('a', 'nope', nodes), isEmpty);
      expect(RouteCalculator.dijkstra('nope', 'a', nodes), isEmpty);
    });

    test('遠回りより近道を選ぶ', () {
      // start -(近道)- goal
      //   \-- far1 -- far2 --/
      final g = <String, dynamic>{
        'start': _node(0, 0, ['goal', 'far1']),
        'goal': _node(1, 0, ['start', 'far2']),
        'far1': _node(0, 5, ['start', 'far2']),
        'far2': _node(1, 5, ['far1', 'goal']),
      };
      expect(RouteCalculator.dijkstra('start', 'goal', g), ['start', 'goal']);
    });
  });

  group('dijkstraToAny', () {
    // near は2歩、far は4歩の位置に置く。
    final nodes = <String, dynamic>{
      's': _node(0, 0, ['m']),
      'm': _node(1, 0, ['s', 'near', 'x']),
      'near': _node(2, 0, ['m']),
      'x': _node(1, 1, ['m', 'y']),
      'y': _node(1, 2, ['x', 'far']),
      'far': _node(1, 3, ['y']),
    };

    test('候補のうち最も近いものへ着く', () {
      final path = RouteCalculator.dijkstraToAny('s', {'near', 'far'}, nodes);
      expect(path.last, 'near');
    });

    test('始点自身が候補なら即終了', () {
      expect(RouteCalculator.dijkstraToAny('s', {'s'}, nodes), ['s']);
    });

    test('候補が空なら空', () {
      expect(RouteCalculator.dijkstraToAny('s', <String>{}, nodes), isEmpty);
    });

    test('どの候補にも届かなければ空', () {
      expect(RouteCalculator.dijkstraToAny('s', {'unknown'}, nodes), isEmpty);
    });
  });
}
