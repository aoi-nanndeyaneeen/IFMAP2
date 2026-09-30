import 'package:flutter_test/flutter_test.dart';
import 'package:ifmap/routing/route_planner.dart';

Map<String, dynamic> _node(int x, int y, List<String> edges,
        [Map<String, dynamic> extra = const {}]) =>
    {'x': x * 10, 'y': y * 10, 'edges': edges, ...extra};

/// 1F: start -- stair1F
/// 2F: stair2F -- goal
/// 階段は両フロアで同じ name ('階段A') を持たせて対応づける。
Map<String, Map<String, dynamic>> _twoFloorsWithStairs() => {
      'F1': {
        'start': _node(0, 0, ['s1']),
        's1': _node(1, 0, ['start'], {'isStairs': true, 'name': '階段A'}),
      },
      'F2': {
        's2': _node(1, 0, ['goal'], {'isStairs': true, 'name': '階段A'}),
        'goal': _node(2, 0, ['s2']),
      },
    };

void main() {
  const labels = ['F1', 'F2', 'F3'];

  group('同一フロア', () {
    test('そのフロアの経路だけを返す', () {
      final result = RoutePlanner.plan(RoutePlanRequest(
        nodesByLabel: {
          'F1': {
            'a': _node(0, 0, ['b']),
            'b': _node(1, 0, ['a']),
          }
        },
        sectionLabels: labels,
        startId: 'a',
        goalId: 'b',
        startLabel: 'F1',
        goalLabel: 'F1',
      ));
      expect(result.keys, ['F1']);
      expect(result['F1'], ['a', 'b']);
    });
  });

  group('階をまたぐ', () {
    test('名前の一致する階段を経由して両フロアの経路を返す', () {
      final result = RoutePlanner.plan(RoutePlanRequest(
        nodesByLabel: _twoFloorsWithStairs(),
        sectionLabels: labels,
        startId: 'start',
        goalId: 'goal',
        startLabel: 'F1',
        goalLabel: 'F2',
      ));
      expect(result['F1'], ['start', 's1']);
      expect(result['F2'], ['s2', 'goal']);
    });

    test('下りも同じように扱える', () {
      final result = RoutePlanner.plan(RoutePlanRequest(
        nodesByLabel: _twoFloorsWithStairs(),
        sectionLabels: labels,
        startId: 'goal',
        goalId: 'start',
        startLabel: 'F2',
        goalLabel: 'F1',
      ));
      expect(result['F2'], ['goal', 's2']);
      expect(result['F1'], ['s1', 'start']);
    });

    test('接続点があれば階段より優先する', () {
      final nodes = {
        'F1': {
          'start': _node(0, 0, ['c1', 's1']),
          'c1': _node(1, 0, ['start'],
              {'isConnector': true, 'name': '渡り廊下', 'connectsToMap': 'F2'}),
          's1': _node(0, 1, ['start'], {'isStairs': true, 'name': '階段A'}),
        },
        'F2': {
          'c2': _node(1, 0, ['goal'],
              {'isConnector': true, 'name': '渡り廊下', 'connectsToMap': 'F1'}),
          's2': _node(0, 1, <String>[], {'isStairs': true, 'name': '階段A'}),
          'goal': _node(2, 0, ['c2']),
        },
      };
      final result = RoutePlanner.plan(RoutePlanRequest(
        nodesByLabel: nodes,
        sectionLabels: labels,
        startId: 'start',
        goalId: 'goal',
        startLabel: 'F1',
        goalLabel: 'F2',
      ));
      expect(result['F1']!.last, 'c1');
      expect(result['F2']!.first, 'c2');
    });

    test('3フロア分を通しで組み立てる', () {
      final nodes = {
        'F1': {
          'start': _node(0, 0, ['a1']),
          'a1': _node(1, 0, ['start'], {'isStairs': true, 'name': '階段A'}),
        },
        'F2': {
          'a2': _node(1, 0, ['b2'], {'isStairs': true, 'name': '階段A'}),
          'b2': _node(2, 0, ['a2'], {'isStairs': true, 'name': '階段B'}),
        },
        'F3': {
          'b3': _node(2, 0, ['goal'], {'isStairs': true, 'name': '階段B'}),
          'goal': _node(3, 0, ['b3']),
        },
      };
      final result = RoutePlanner.plan(RoutePlanRequest(
        nodesByLabel: nodes,
        sectionLabels: labels,
        startId: 'start',
        goalId: 'goal',
        startLabel: 'F1',
        goalLabel: 'F3',
      ));
      expect(result.keys.toSet(), {'F1', 'F2', 'F3'});
      expect(result['F2'], ['a2', 'b2']);
      expect(result['F3']!.last, 'goal');
    });

    test('最寄りの階段の先が行き止まりなら、目的地に届く階段を選ぶ', () {
      // 実マップで起きたこと: 3F で最寄りの中央階段を選ぶと、1F では
      // 中央階段側と目的地側の通路がつながっておらず行き止まりになった。
      // F1: start -- a1(階段A)        すぐ隣
      //     start -- m1 -- m2 -- b1(階段B)  遠い
      // F2: a2(階段A) は孤立。b2(階段B) -- goal
      final nodes = {
        'F1': {
          'start': _node(0, 0, ['a1', 'm1']),
          'a1': _node(1, 0, ['start'], {'isStairs': true, 'name': '階段A'}),
          'm1': _node(0, 1, ['start', 'm2']),
          'm2': _node(0, 2, ['m1', 'b1']),
          'b1': _node(0, 3, ['m2'], {'isStairs': true, 'name': '階段B'}),
        },
        'F2': {
          'a2': _node(1, 0, <String>[], {'isStairs': true, 'name': '階段A'}),
          'b2': _node(0, 3, ['goal'], {'isStairs': true, 'name': '階段B'}),
          'goal': _node(1, 3, ['b2']),
        },
      };
      final result = RoutePlanner.plan(RoutePlanRequest(
        nodesByLabel: nodes,
        sectionLabels: labels,
        startId: 'start',
        goalId: 'goal',
        startLabel: 'F1',
        goalLabel: 'F2',
      ));
      expect(result['F1'], ['start', 'm1', 'm2', 'b1']);
      expect(result['F2'], ['b2', 'goal']);
    });

    test('途中のフロアを歩いて別の階段に乗り換えられる', () {
      // 3F -(中央階段)-> 2F を歩く -(情報棟階段)-> 1F、の形。
      final nodes = {
        'F1': {
          'x1': _node(5, 0, ['goal'], {'isStairs': true, 'name': '情報棟階段'}),
          'c1': _node(0, 0, <String>[], {'isStairs': true, 'name': '中央階段'}),
          'goal': _node(6, 0, ['x1']),
        },
        'F2': {
          'c2': _node(0, 0, ['w'], {'isStairs': true, 'name': '中央階段'}),
          'w': _node(2, 0, ['c2', 'x2']),
          'x2': _node(5, 0, ['w'], {'isStairs': true, 'name': '情報棟階段'}),
        },
        'F3': {
          'start': _node(0, 1, ['c3']),
          'c3': _node(0, 0, ['start'], {'isStairs': true, 'name': '中央階段'}),
        },
      };
      final result = RoutePlanner.plan(RoutePlanRequest(
        nodesByLabel: nodes,
        sectionLabels: labels,
        startId: 'start',
        goalId: 'goal',
        startLabel: 'F3',
        goalLabel: 'F1',
      ));
      expect(result['F3'], ['start', 'c3']);
      expect(result['F2'], ['c2', 'w', 'x2']);
      expect(result['F1'], ['x1', 'goal']);
    });

    test('別の建物へは、屋外を通って並びの離れたフロアへ行ける', () {
      // 並び: 寮2F, 寮1F, 本棟1F, 本棟2F, 屋外
      // 寮2F -(階段)-> 寮1F -(玄関)-> 屋外 -(入口)-> 本棟1F -(階段)-> 本棟2F
      final nodes = {
        'D2': {
          'start': _node(0, 0, ['ds2']),
          'ds2': _node(1, 0, ['start'], {'isStairs': true, 'name': '寮_階段'}),
        },
        'D1': {
          'ds1': _node(1, 0, ['dg'], {'isStairs': true, 'name': '寮_階段'}),
          'dg': _node(2, 0, ['ds1'],
              {'isConnector': true, 'name': '寮玄関', 'connectsToMap': 'OUT'}),
        },
        'M1': {
          'mg': _node(0, 0, ['ms1'],
              {'isConnector': true, 'name': '本棟入口', 'connectsToMap': 'OUT'}),
          'ms1': _node(1, 0, ['mg'], {'isStairs': true, 'name': '本棟_階段'}),
        },
        'M2': {
          'ms2': _node(1, 0, ['goal'], {'isStairs': true, 'name': '本棟_階段'}),
          'goal': _node(2, 0, ['ms2']),
        },
        'OUT': {
          'od': _node(0, 0, ['r'],
              {'isConnector': true, 'name': '寮玄関', 'connectsToMap': 'D1'}),
          'r': _node(5, 0, ['od', 'om']),
          'om': _node(9, 0, ['r'],
              {'isConnector': true, 'name': '本棟入口', 'connectsToMap': 'M1'}),
        },
      };
      final request = RoutePlanRequest(
        nodesByLabel: nodes,
        sectionLabels: const ['D2', 'D1', 'M1', 'M2', 'OUT'],
        startId: 'start',
        goalId: 'goal',
        startLabel: 'D2',
        goalLabel: 'M2',
      );
      final result = RoutePlanner.plan(request);
      expect(result.keys, ['D2', 'D1', 'OUT', 'M1', 'M2']);
      expect(result['OUT'], ['od', 'r', 'om']);
      expect(result['M2']!.last, 'goal');
      // 寮1F と本棟1F は並びで隣り合っているが、階段の名前が違うので直接は行けない。
      expect(RoutePlanner.floorGraph(nodes, request.sectionLabels)['D1'], {'D2', 'OUT'});
      // Isolate に渡す前の絞り込みでも、屋外は残る。
      expect(RoutePlanner.planFromMessage(request.trimmed().toMessage()), result);
    });

    test('階段も接続点もなければ途中で打ち切る', () {
      final result = RoutePlanner.plan(RoutePlanRequest(
        nodesByLabel: {
          'F1': {'start': _node(0, 0, <String>[])},
          'F2': {'goal': _node(0, 0, <String>[])},
        },
        sectionLabels: labels,
        startId: 'start',
        goalId: 'goal',
        startLabel: 'F1',
        goalLabel: 'F2',
      ));
      expect(result, isEmpty);
    });
  });

  group('trimmed', () {
    test('経路に使われうるフロアのノードだけを残す', () {
      final request = RoutePlanRequest(
        nodesByLabel: {
          'F1': {'a': _node(0, 0, <String>[])},
          'F2': {'b': _node(0, 0, <String>[])},
          'F3': {'c': _node(0, 0, <String>[])},
        },
        sectionLabels: labels,
        startId: 'a',
        goalId: 'b',
        startLabel: 'F1',
        goalLabel: 'F2',
      );
      final trimmed = request.trimmed();
      expect(trimmed.nodesByLabel.keys.toSet(), {'F1', 'F2'});
      // 並びは階段の隣り合いを表すのでそのまま。
      expect(trimmed.sectionLabels, labels);
    });

    test('往復してもメッセージ経由で同じ結果になる', () {
      final request = RoutePlanRequest(
        nodesByLabel: _twoFloorsWithStairs(),
        sectionLabels: labels,
        startId: 'start',
        goalId: 'goal',
        startLabel: 'F1',
        goalLabel: 'F2',
      );
      final direct = RoutePlanner.plan(request);
      final viaMessage =
          RoutePlanner.planFromMessage(request.trimmed().toMessage());
      expect(viaMessage, direct);
    });
  });

  group('connectorsTo / matchingStairs', () {
    test('行き先の一致する接続点だけを拾う', () {
      final nodes = {
        'ok': _node(0, 0, <String>[], {'isConnector': true, 'connectsToMap': 'F2'}),
        'other': _node(1, 0, <String>[], {'isConnector': true, 'connectsToMap': 'F9'}),
        'plain': _node(2, 0, <String>[]),
      };
      expect(RoutePlanner.connectorsTo(nodes, 'F2'), {'ok'});
    });

    test('両フロアに同じ名前がある階段だけを候補にする', () {
      final from = {
        'sA': _node(0, 0, <String>[], {'isStairs': true, 'name': 'A'}),
        'sB': _node(1, 0, <String>[], {'isStairs': true, 'name': 'B'}),
      };
      final to = {
        'tA': _node(0, 0, <String>[], {'isStairs': true, 'name': 'A'}),
      };
      expect(RoutePlanner.matchingStairs(from, to), {'sA'});
    });

    test('名前が一致しなければ自フロアの階段を全部候補にする', () {
      final from = {
        'sA': _node(0, 0, <String>[], {'isStairs': true, 'name': 'A'}),
        'sB': _node(1, 0, <String>[], {'isStairs': true, 'name': 'B'}),
      };
      expect(RoutePlanner.matchingStairs(from, const {}), {'sA', 'sB'});
    });
  });
}
